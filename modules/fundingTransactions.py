import json
from fastapi.responses import JSONResponse
from databases import connection
from modules.azure_notifications import send_azure_push
from modules.pushNotifications import resolve_push_user_ids
from modules.loanTickets import notify_funding_event_async
from modules.loanPush import push_in_background
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
            "EXEC [dbo].[sp_userCompanies_role] @pjsonfile = %s",
            (json.dumps({"userCompanies": [{"userId": requester_user_id, "companyId": company_id}]}),)
        )
        row = cursor.fetchone()
        result = json.loads(row[0]) if row and row[0] else {}
        if "error" in result:
            raise RuntimeError(result["error"])
        return result.get("roleName")
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


def funding_transactions_declare(json_file: dict):
    """sp_fundingTransactions 'declare' + the RFC-014 ticket to both parties
    (lender: "Fondeo declarado"; borrower: "Confirma tu fondeo"). The ticket
    runs in the background and never changes this response.
    RFC-016 fase 3b: refused while the loan's platform fee isn't PAID."""
    from modules.platformFees import require_fee_paid
    req = (json_file.get("fundingTransactions") or [{}])[0]
    blocked = require_fee_paid(req.get("companyId"), req.get("loanId"))
    if blocked:
        return JSONResponse(content={"error": blocked, "code": "PLATFORM_FEE_UNPAID"}, status_code=409)
    result = _sp_raw(json_file)
    funding_id = result.get("fundingTransactionId") if isinstance(result, dict) else None
    if funding_id and "error" not in result:
        company_id = result.get("companyId") or (json_file.get("fundingTransactions") or [{}])[0].get("companyId")
        try:
            # Core push to the borrower: confirm whether the SPEI arrived.
            push_in_background(company_id, result.get("borrowerClientId"), "funding_declared",
                               amount=result.get("amountMXN"), loanId=result.get("loanId"),
                               fundingTransactionId=funding_id)
            # Ticket (email always; WhatsApp/SMS only for parties without the app).
            notify_funding_event_async(company_id, funding_id, "declared")
        except Exception as e:
            print(f"[fundingTransactions] declare notices not started: {e}")
    return JSONResponse(content=result, status_code=200)


async def _push_loan_active(ft: dict, loan_id) -> None:
    """Core push (send_azure_push) "Préstamo activo" to borrower and lender.
    Hub tags are user_{userId}; the funding row has CLIENT ids — resolve first
    (RFC-014 P1). Best-effort: never changes the confirm response."""
    parties = [(ft.get("borrowerClientId"), "borrower"), (ft.get("lenderClientId"), "lender")]
    client_ids = [cid for cid, _ in parties if cid]
    if not client_ids:
        return
    try:
        conn = _conn()
        try:
            user_ids = resolve_push_user_ids(conn.cursor(), client_ids)
        finally:
            conn.close()
    except Exception as e:
        print(f"[fundingTransactions] confirm push: resolve users failed: {e}")
        return
    amount = float(ft.get("amountMXN") or 0)
    for client_id, role in parties:
        user_id = user_ids.get(client_id) or user_ids.get(str(client_id)) if client_id else None
        if not user_id:
            print(f"[fundingTransactions] confirm push skipped ({role}): no app user")
            continue
        try:
            await send_azure_push(
                "✅ Préstamo activo",
                f"El fondeo de ${amount:,.2f} fue confirmado. El préstamo está activo.",
                user_id,
                data={"navigationRoute": f"/loan-detail/{loan_id}"},
            )
        except Exception as e:
            print(f"[fundingTransactions] confirm push failed ({role}): {e}")


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
        notify_funding_event_async(company_id, funding_id, "confirmed", None)
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
        notify_funding_event_async(company_id, funding_id, "confirmed", None)
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
            await _push_loan_active(ft, loan_id)
        else:
            response["warning"] = f"Calendario generado pero la activación falló: {activate_result['error']}"
    else:
        response["warning"] = "Calendario de pagos no se pudo generar — préstamo queda en 'funded', requiere revisión manual."
        print(f"[fundingTransactions] schedule generation failed for loanId={loan_id}: {schedule_body}")

    # RFC-014: ticket to both parties through notificationDispatch (push ->
    # WhatsApp -> SMS, resolving clientId -> userId for the push) + email.
    # Replaces the direct "Préstamo activo" push (RFC-014 P1). Background only.
    try:
        notify_funding_event_async(company_id, funding_id, "confirmed", response["loanStatus"])
    except Exception as e:
        print(f"[fundingTransactions] confirm ticket not started: {e}")

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
