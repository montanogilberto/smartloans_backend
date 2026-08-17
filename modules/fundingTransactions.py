import json
from fastapi.responses import JSONResponse
from databases import connection
from modules.azure_notifications import send_azure_push
from modules.automatedPayments import generate_installment_schedule


def _conn():
    return connection()


def _sp_raw(json_file: dict):
    """Low-level sp_fundingTransactions call, returns a parsed dict (not a
    JSONResponse) so orchestration code below can compose calls."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_fundingTransactions] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {"error": "no result"}
    except Exception as e:
        return {"error": str(e)}
    finally:
        if conn:
            conn.close()


def _sp_loans_transition(loan_id: int, company_id: int, to_status: str):
    """sp_loans action=4 (transition) — D6 validity-matrix-gated status
    change. See sql/sp_loans.sql."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loans] @pjsonfile = %s",
            (json.dumps({"loans": [{
                "action": 4, "loanId": loan_id, "companyId": company_id, "toStatus": to_status,
            }]}),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {"error": "no result"}
    except Exception as e:
        return {"error": str(e)}
    finally:
        if conn:
            conn.close()


def _sp_loans_one(loan_id: int, company_id: int):
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loans_one] @pjsonfile = %s",
            (json.dumps({"loans": [{"loanId": loan_id, "companyId": company_id}]}),)
        )
        row = cursor.fetchone()
        result = json.loads(row[0]) if row and row[0] else {"loans": []}
        loans = result.get("loans", [])
        return loans[0] if loans else None
    except Exception:
        return None
    finally:
        if conn:
            conn.close()


def _requester_role(company_id: int, requester_user_id: int):
    """sp_login's own source of truth for role: dbo.userCompanies, not
    dbo.users (see sql/sp_users.sql comment: 'sp_login reads role/company/
    branch from here, not from dbo.users')."""
    if not requester_user_id:
        return None
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT TOP 1 roleName FROM dbo.userCompanies "
            "WHERE userId = %s AND companyId = %s AND active = 1",
            (requester_user_id, company_id)
        )
        row = cursor.fetchone()
        return row[0] if row else None
    except Exception as e:
        print(f"[fundingTransactions] _requester_role failed: {e}")
        return None
    finally:
        if conn:
            conn.close()


def funding_transactions_sp(json_file: dict):
    """declare | reject | escalate_due | list | one via sp_fundingTransactions
    — plain passthrough. 'confirm' and 'resolve_escalation' are handled by
    their own async orchestration functions below (see routes_/fundingTransactions.py)
    because they need extra steps beyond this one SP call."""
    return JSONResponse(content=_sp_raw(json_file), status_code=200)


async def funding_transactions_confirm(json_file: dict):
    """Orchestrates fundingTransactions.confirm -> sp_loans transition ->
    PaymentSchedule generation -> loan active (D13, payment-domain-state-
    machines.md §2.1 footnote 1: FUNDED and ACTIVE are deliberately not the
    same instant). sp_fundingTransactions.confirm itself only updates its own
    table + paymentHistory (D16) — this is "the calling Python module" that
    file's comments refer to."""
    item = (json_file.get("fundingTransactions") or [{}])[0]
    company_id = item.get("companyId")

    confirm_result = _sp_raw(json_file)
    if "error" in confirm_result:
        return JSONResponse(content=confirm_result, status_code=400)

    loan_id = confirm_result.get("loanId")
    funding_id = confirm_result.get("fundingTransactionId")

    # Fetch the full funding row (confirm's own result is deliberately thin)
    # for the amount/parties PaymentSchedule generation needs.
    ft = _sp_raw({"fundingTransactions": [{
        "action": "one", "companyId": company_id, "fundingTransactionId": funding_id,
    }]})
    loan = _sp_loans_one(loan_id, company_id)

    if "error" in ft or not loan:
        # Funding IS confirmed at this point (the SP call above already
        # committed) — a failure here is an orchestration problem, not a
        # funding problem. Surface it distinctly so it isn't mistaken for a
        # rejected confirmation; the loan stays in whatever status it was.
        return JSONResponse(content={
            "fundingTransactionId": funding_id, "loanId": loan_id, "status": "CONFIRMED",
            "warning": "Fondeo confirmado, pero no se pudo leer el préstamo/fondeo completo para activar el calendario. Requiere revisión manual.",
        }, status_code=200)

    transition_result = _sp_loans_transition(loan_id, company_id, "funded")
    if "error" in transition_result:
        return JSONResponse(content={
            "fundingTransactionId": funding_id, "loanId": loan_id, "status": "CONFIRMED",
            "warning": f"Fondeo confirmado, pero la transición del préstamo a 'funded' falló: {transition_result['error']}",
        }, status_code=200)

    schedule_result = await generate_installment_schedule({
        "loanId": loan_id,
        "clientId": ft.get("borrowerClientId"),
        "companyId": company_id,
        "lenderId": ft.get("lenderClientId"),
        "principalAmount": loan.get("principalAmount"),
        "interestRate": loan.get("interestRate"),
        "termMonths": loan.get("termMonths"),
        "disbursementDate": ft.get("transferDate"),
    })
    schedule_body = json.loads(schedule_result.body) if hasattr(schedule_result, "body") else {}
    schedule_failed = schedule_result.status_code >= 400 if hasattr(schedule_result, "status_code") else True

    response = {
        "fundingTransactionId": funding_id, "loanId": loan_id,
        "fundingStatus": "CONFIRMED", "loanStatus": "funded",
    }

    if not schedule_failed:
        activate_result = _sp_loans_transition(loan_id, company_id, "active")
        if "error" not in activate_result:
            response["loanStatus"] = "active"
            for uid, role in [(ft.get("borrowerClientId"), "borrower"), (ft.get("lenderClientId"), "lender")]:
                if uid:
                    try:
                        await send_azure_push(
                            "✅ Préstamo activo",
                            f"El fondeo de ${ft.get('amountMXN', 0):,.2f} fue confirmado. El préstamo está activo.",
                            uid,
                        )
                    except Exception as e:
                        print(f"[fundingTransactions] confirm push failed ({role}): {e}")
        else:
            response["warning"] = f"Calendario generado pero la activación falló: {activate_result['error']}"
    else:
        response["warning"] = "Calendario de pagos no se pudo generar — préstamo queda en 'funded', requiere revisión manual."
        print(f"[fundingTransactions] schedule generation failed for loanId={loan_id}: {schedule_body}")

    return JSONResponse(content=response, status_code=200)


async def funding_transactions_resolve_escalation(json_file: dict):
    """RBAC gate in front of sp_fundingTransactions resolve_escalation
    (support/admin only — the SP itself does not check this, per
    sql/sp_fundingTransactions.sql's own comment on @resolverUserId)."""
    item = (json_file.get("fundingTransactions") or [{}])[0]
    company_id = item.get("companyId")
    resolver_user_id = item.get("resolverUserId")

    role = _requester_role(company_id, resolver_user_id)
    # "support" has no dedicated roleCode in this app's taxonomy
    # (src/config/rolePermissions.ts: admin|manager|employee) — admin/manager
    # are treated as the support-equivalent roles until a dedicated one exists.
    if role not in ("admin", "manager"):
        return JSONResponse(
            content={"error": "Solo soporte/admin puede resolver un escalamiento."},
            status_code=403,
        )

    return JSONResponse(content=_sp_raw(json_file), status_code=200)
