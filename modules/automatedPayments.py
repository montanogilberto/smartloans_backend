"""
Automated Payment Collection — POS GMO P2P Lending

Flow:
  1. After first successful repayment, save borrower's Stripe payment method
     via SetupIntent → stored as stripePaymentMethodId in SQL
  2. When loan is created, generate an installment schedule (one row per payment date)
  3. A daily cron job (Azure Function / APScheduler) calls /automated-payments/charge-due
     which finds due installments and charges the saved card automatically
  4. Success → update installment status + notify lender
  5. Failure → retry next day for up to 3 attempts, then mark as delinquent

Tables required:
  savedPaymentMethods  (clientId, stripePaymentMethodId, last4, brand, expiryMonth, expiryYear)
  loanInstallments     (installmentId, loanId, clientId, companyId, dueDate, amount,
                        principal, interest, status, stripePaymentIntentId,
                        attemptCount, lastAttemptAt, paidAt)
"""

import os
import json
import traceback
import stripe
from fastapi.responses import JSONResponse
from databases import connection
from datetime import datetime, timezone, date
from decimal import Decimal, ROUND_HALF_UP
from dateutil.relativedelta import relativedelta
from modules.stripe_payments import _sp_connected_accounts
from modules.walletBalance import credit_wallet
from observability.logger import log_workflow_step, log_integration

stripe.api_key = os.getenv("STRIPE_SECRET_KEY", "")
MAX_RETRY_ATTEMPTS = 3


def _conn():
    return connection()


def _sp_installments(payload: dict) -> dict:
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanInstallments] @pjsonfile = %s",
            (json.dumps({"installments": [payload]}),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        print(f"[automatedPayments] installments SP error: {e}")
        return {}
    finally:
        if conn:
            conn.close()


def _installment_one(company_id: int, loan_id: int, installment_id: int) -> dict:
    """Full installment row via sp_loanInstallments_one ({} if not found).
    Raises on DB/SP error — unlike _sp_installments, a failure here must not
    look like "cuota no encontrada" on the money path."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanInstallments_one] @pjsonfile = %s",
            (json.dumps({"installments": [{
                "installmentId": installment_id, "loanId": loan_id, "companyId": company_id,
            }]}),)
        )
        row = cursor.fetchone()
        result = json.loads(row[0]) if row and row[0] else {}
        if "error" in result:
            raise RuntimeError(f"sp_loanInstallments_one: {result['error']}")
        return result
    finally:
        if conn:
            conn.close()


def _sp_saved_methods(payload: dict) -> dict:
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_savedPaymentMethods] @pjsonfile = %s",
            (json.dumps({"paymentMethods": [payload]}),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        print(f"[automatedPayments] savedMethods SP error: {e}")
        return {}
    finally:
        if conn:
            conn.close()


# ── SetupIntent (save card for future charges) ───────────────────────────────

async def create_setup_intent(payload: dict):
    """
    Creates a Stripe SetupIntent so the borrower can save their card.
    Frontend confirms with Stripe.js, then calls /automated-payments/save-method.

    POST /automated-payments/setup-intent
    Body: { "clientId": int, "companyId": int }
    Returns: { "clientSecret": str, "setupIntentId": str }
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")

    if not stripe.api_key or stripe.api_key.startswith("sk_test_YOUR"):
        mock_id = f"seti_mock_{int(datetime.now(timezone.utc).timestamp())}"
        return JSONResponse({
            "clientSecret": f"{mock_id}_secret_mock",
            "setupIntentId": mock_id,
        }, status_code=200)

    try:
        setup_intent = stripe.SetupIntent.create(
            usage="off_session",   # allows future off-session charges
            metadata={
                "clientId":  str(client_id),
                "companyId": str(company_id),
            },
            payment_method_types=["card"],
        )
        return JSONResponse({
            "clientSecret":  setup_intent["client_secret"],
            "setupIntentId": setup_intent["id"],
        }, status_code=200)
    except stripe.StripeError as e:
        return JSONResponse({"error": str(e)}, status_code=400)


async def save_payment_method(payload: dict):
    """
    After SetupIntent confirmed by frontend, save the payment method ID.

    POST /automated-payments/save-method
    Body: { "clientId": int, "companyId": int, "setupIntentId": str }
    Returns: { "paymentMethod": { last4, brand, expiryMonth, expiryYear } }
    """
    client_id      = payload.get("clientId")
    company_id     = payload.get("companyId")
    setup_intent_id = payload.get("setupIntentId")

    if not setup_intent_id or setup_intent_id.startswith("seti_mock_"):
        result = _sp_saved_methods({
            "action": "upsert",
            "clientId": client_id,
            "companyId": company_id,
            "stripePaymentMethodId": "pm_mock_card",
            "last4": "4242",
            "brand": "visa",
            "expiryMonth": 12,
            "expiryYear": 2030,
        })
        return JSONResponse({"paymentMethod": result}, status_code=200)

    try:
        si = stripe.SetupIntent.retrieve(setup_intent_id)

        # Use attribute access, not dict .get(): Stripe response objects are
        # version-sensitive about the dict interface, and the previous
        # si.get(...)/pm.get(...) path was failing with an opaque error (the
        # 500 body was just "get"). payment_method may be an id string OR, if
        # the SetupIntent was expanded, a full object — handle both.
        pm_field = getattr(si, "payment_method", None)
        pm_id = getattr(pm_field, "id", None) or pm_field
        if not pm_id:
            return JSONResponse({"error": "SetupIntent has no payment method attached"}, status_code=400)

        pm = stripe.PaymentMethod.retrieve(pm_id)
        card = getattr(pm, "card", None)

        result = _sp_saved_methods({
            "action": "upsert",
            "clientId": client_id,
            "companyId": company_id,
            "stripePaymentMethodId": pm_id,
            "last4":       getattr(card, "last4", "") if card else "",
            "brand":       getattr(card, "brand", "") if card else "",
            "expiryMonth": getattr(card, "exp_month", None) if card else None,
            "expiryYear":  getattr(card, "exp_year", None) if card else None,
        })

        return JSONResponse({"paymentMethod": result}, status_code=200)

    except stripe.StripeError as e:
        print(f"[automatedPayments] save_method Stripe error: {type(e).__name__}: {e}")
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        # Log the real cause (type + repr + traceback). The old handler
        # returned a bare str(e), which surfaced on-device as the useless
        # message "get" with nothing to trace it to.
        print(f"[automatedPayments] save_method FAILED: {type(e).__name__}: {e!r}\n{traceback.format_exc()}")
        return JSONResponse({"error": f"{type(e).__name__}: {e}"}, status_code=500)


async def get_saved_method(payload: dict):
    """GET the saved payment method for a client."""
    result = _sp_saved_methods({
        "action": "get",
        "clientId": payload.get("clientId"),
        "companyId": payload.get("companyId"),
    })
    return JSONResponse({"paymentMethod": result or None}, status_code=200)


# ── Installment Schedule ─────────────────────────────────────────────────────

async def generate_installment_schedule(payload: dict):
    """
    Generate amortization schedule for a loan and persist to loanInstallments table.

    POST /automated-payments/generate-schedule
    Body: {
      "loanId": int, "clientId": int, "companyId": int, "lenderId": int,
      "principalAmount": float, "interestRate": float (annual %),
      "termMonths": int, "disbursementDate": str (ISO)
    }
    """
    loan_id    = payload.get("loanId")
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    lender_id  = payload.get("lenderId")
    principal  = float(payload.get("principalAmount", 0))
    annual_rate = float(payload.get("interestRate", 0))
    term_months = int(payload.get("termMonths", 1))
    start_str   = payload.get("disbursementDate", datetime.now(timezone.utc).isoformat())

    if not principal or not term_months:
        return JSONResponse({"error": "principalAmount and termMonths required"}, status_code=400)

    monthly_rate = annual_rate / 100 / 12
    start_date = datetime.fromisoformat(start_str.replace("Z", "+00:00")).date()

    # French amortization formula
    if monthly_rate > 0:
        monthly_payment = principal * (monthly_rate * (1 + monthly_rate) ** term_months) \
                          / ((1 + monthly_rate) ** term_months - 1)
    else:
        monthly_payment = principal / term_months

    balance = principal
    installments = []

    for i in range(1, term_months + 1):
        due_date     = start_date + relativedelta(months=i)
        interest_amt = round(balance * monthly_rate, 2)
        principal_amt = round(min(monthly_payment - interest_amt, balance), 2)
        payment_amt  = round(principal_amt + interest_amt, 2)
        balance      = round(max(0, balance - principal_amt), 2)

        result = _sp_installments({
            "action":          "insert",
            "loanId":          loan_id,
            "clientId":        client_id,
            "companyId":       company_id,
            "lenderId":        lender_id,
            "installmentNumber": i,
            "dueDate":         due_date.isoformat(),
            "amount":          payment_amt,
            "principal":       principal_amt,
            "interest":        interest_amt,
            "remainingBalance": balance,
            "status":          "pending",
        })
        installments.append({
            "installmentNumber": i,
            "dueDate":           due_date.isoformat(),
            "amount":            payment_amt,
            "principal":         principal_amt,
            "interest":          interest_amt,
            "remainingBalance":  balance,
        })

    return JSONResponse({
        "loanId":            loan_id,
        "termMonths":        term_months,
        "monthlyPayment":    round(monthly_payment, 2),
        "totalRepayment":    round(monthly_payment * term_months, 2),
        "totalInterest":     round(monthly_payment * term_months - principal, 2),
        "installments":      installments,
    }, status_code=200)


async def get_installment_schedule(payload: dict):
    """GET the installment schedule for a loan."""
    loan_id    = payload.get("loanId")
    company_id = payload.get("companyId")
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanInstallments] @pjsonfile = %s",
            (json.dumps({"installments": [{
                "action":    "list",
                "loanId":    loan_id,
                "companyId": company_id,
            }]}),)
        )
        rows = cursor.fetchall()
        json_result = "".join(r[0] for r in rows if r and r[0])
        return JSONResponse(
            json.loads(json_result) if json_result else {"installments": []},
            status_code=200,
        )
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


# ── SPEI repayment (primary rail — user decision: "only we use STP") ─────────

async def pay_installment_spei(payload: dict):
    """
    Pays ONE installment through the STP/SPEI rail: debits the borrower's
    wallet and credits the lender's wallet in the immutable ledger, then marks
    the installment paid. No card, no Stripe. The card auto-charge below stays
    as the dormant 2nd option.

    POST /automated-payments/pay-spei
    Body: { "companyId": int, "loanId": int, "installmentId": int, "clientId": int }
    """
    from modules.walletTransactions import post_entry, get_balance
    from modules.azure_notifications import send_azure_push
    from modules.pushNotifications import resolve_push_user_ids

    company_id  = int(payload.get("companyId", 0))
    loan_id     = int(payload.get("loanId", 0))
    inst_id     = int(payload.get("installmentId", 0))
    borrower_id = int(payload.get("clientId", 0))
    if not (company_id and loan_id and inst_id and borrower_id):
        return JSONResponse({"error": "companyId, loanId, installmentId y clientId son requeridos"}, status_code=400)

    # The SP's 'list' action omits clientId/lenderId — sp_loanInstallments_one
    # returns the full row for ownership + counterpart.
    row = _installment_one(company_id, loan_id, inst_id)
    if not row:
        return JSONResponse({"error": f"Cuota {inst_id} no encontrada en el préstamo {loan_id}"}, status_code=404)
    inst_client_id, lender_id, inst_number = int(row["clientId"]), int(row["lenderId"]), int(row["installmentNumber"])
    amount, principal, interest = float(row["amount"]), float(row.get("principal") or 0), float(row.get("interest") or 0)
    inst_status, attempt_count = row.get("status"), int(row.get("attemptCount") or 0)
    if inst_client_id != borrower_id:
        return JSONResponse({"error": "La cuota no pertenece a este cliente"}, status_code=403)
    if inst_status == "paid":
        return JSONResponse({"paid": True, "replayed": True, "installmentId": inst_id}, status_code=200)
    inst = {"installmentNumber": inst_number, "attemptCount": attempt_count}

    bal = get_balance(company_id, borrower_id)
    available = float(bal.get("availableBalance", 0))
    if available < amount:
        return JSONResponse({
            "error": f"Saldo insuficiente: la cuota es de ${amount:,.2f} y tu billetera tiene ${available:,.2f}. Deposita por SPEI primero.",
            "availableBalance": available, "amount": amount,
        }, status_code=402)

    debit = post_entry(
        company_id=company_id, client_id=borrower_id,
        entry_type="LOAN_REPAYMENT", direction="D", amount_mxn=amount,
        idempotency_key=f"cuota:{inst_id}:borrower",
        reference_type="loanInstallment", reference_id=inst_id,
        note=f"Pago cuota #{inst.get('installmentNumber')} préstamo {loan_id} (SPEI)")
    if debit.get("error"):
        return JSONResponse({"error": debit["error"]}, status_code=400)

    # Lender credit split per the catalog design: principal + interest as
    # separate entries (any rounding residue rides on the principal entry).
    credit_principal = post_entry(
        company_id=company_id, client_id=lender_id,
        entry_type="REPAYMENT_PRINCIPAL", direction="C",
        amount_mxn=round(amount - interest, 2),
        idempotency_key=f"cuota:{inst_id}:lender:principal",
        reference_type="loanInstallment", reference_id=inst_id,
        note=f"Capital cuota #{inst_number} préstamo {loan_id} (SPEI)")
    credit_interest = {"error": None}
    if not credit_principal.get("error") and interest > 0:
        credit_interest = post_entry(
            company_id=company_id, client_id=lender_id,
            entry_type="REPAYMENT_INTEREST", direction="C", amount_mxn=interest,
            idempotency_key=f"cuota:{inst_id}:lender:interest",
            reference_type="loanInstallment", reference_id=inst_id,
            note=f"Interés cuota #{inst_number} préstamo {loan_id} (SPEI)")
    if credit_principal.get("error") or credit_interest.get("error"):
        # The borrower was already debited — reverse so no money is stranded.
        post_entry(
            company_id=company_id, client_id=borrower_id,
            entry_type="REVERSAL", direction="C", amount_mxn=amount,
            idempotency_key=f"cuota:{inst_id}:borrower:reversal",
            reference_type="loanInstallment", reference_id=inst_id,
            note=f"Reversa pago cuota #{inst_number} — abono al prestamista falló")
        err = credit_principal.get("error") or credit_interest.get("error")
        return JSONResponse({"error": f"No se pudo abonar al prestamista (pago revertido): {err}"}, status_code=500)
    credit = credit_interest if interest > 0 and credit_interest.get("balanceAfter") is not None else credit_principal

    _sp_installments({
        "action":        "update_status",
        "installmentId": inst_id,
        "status":        "paid",
        "paidAt":        datetime.now(timezone.utc).isoformat(),
        "attemptCount":  int(inst.get("attemptCount", 0)) + 1,
    })

    # Puntos por pagar puntual. Import perezoso e idempotente por cuota; si
    # falla no se toca el pago, que ya movio dinero.
    try:
        from modules.rewardBenefits import award_on_time_payment
        award_on_time_payment(company_id, borrower_id, inst_id, amount)
    except Exception as _e:
        print(f"[rewards] puntos de cuota {inst_id} omitidos: {_e}")

    try:
        # Hub tags are user_{userId}; lender_id is a CLIENT id — resolve first
        # or the push targets an empty tag and vanishes silently.
        conn = _conn()
        try:
            lender_user_id = resolve_push_user_ids(conn.cursor(), [lender_id]).get(lender_id)
        finally:
            conn.close()
        if lender_user_id:
            await send_azure_push(
                "💵 Cuota recibida",
                f"Cuota #{inst.get('installmentNumber')} de ${amount:,.2f} pagada por SPEI.",
                lender_user_id,
                data={"navigationRoute": "/p2p-lending"})
    except Exception as e:
        print(f"[automatedPayments] pay_installment_spei: push failed: {e}")

    print(f"[automatedPayments] pay_installment_spei: PAID inst={inst_id} ${amount} borrower={borrower_id} → lender={lender_id}")
    return JSONResponse({
        "paid": True, "rail": "spei", "installmentId": inst_id, "amount": amount,
        "borrowerBalanceAfter": debit.get("balanceAfter"),
        "lenderBalanceAfter": credit.get("balanceAfter"),
    }, status_code=200)


# ── Auto-charge due installments (cron job endpoint) ─────────────────────────

async def charge_due_installments(payload: dict):
    """
    Called by Azure scheduled trigger (daily) or manually by admin.
    Finds all pending installments due today or earlier, charges saved card.

    POST /automated-payments/charge-due
    Body: { "companyId": int, "dryRun"?: bool }
    Returns: { "charged": int, "failed": int, "skipped": int, "details": [...] }
    """
    company_id = int(payload.get("companyId", 0))
    dry_run    = bool(payload.get("dryRun", False))
    today      = date.today().isoformat()

    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        # Fetch all due installments
        cursor.execute(
            "EXEC [dbo].[sp_loanInstallments] @pjsonfile = %s",
            (json.dumps({"installments": [{
                "action":    "due",
                "companyId": company_id,
                "asOfDate":  today,
            }]}),)
        )
        rows = cursor.fetchall()
        json_result = "".join(r[0] for r in rows if r and r[0])
        due_items = json.loads(json_result).get("installments", []) if json_result else []
    except Exception as e:
        return JSONResponse({"error": f"Failed to fetch due installments: {e}"}, status_code=500)
    finally:
        if conn:
            conn.close()

    charged = 0
    failed  = 0
    skipped = 0
    details = []

    for item in due_items:
        inst_id   = item.get("installmentId")
        client_id = item.get("clientId")
        lender_id = item.get("lenderId")
        amount_mxn = float(item.get("amount", 0))
        attempts   = int(item.get("attemptCount", 0))

        if attempts >= MAX_RETRY_ATTEMPTS:
            # Mark as delinquent
            _sp_installments({
                "action":         "update_status",
                "installmentId":  inst_id,
                "status":         "delinquent",
                "lastAttemptAt":  datetime.now(timezone.utc).isoformat(),
            })
            skipped += 1
            details.append({"installmentId": inst_id, "result": "delinquent_max_retries"})
            continue

        # Get saved payment method for borrower
        pm_data = _sp_saved_methods({"action": "get", "clientId": client_id, "companyId": company_id})
        pm_id   = pm_data.get("stripePaymentMethodId")

        if not pm_id:
            skipped += 1
            details.append({"installmentId": inst_id, "result": "no_saved_card"})
            continue

        if dry_run:
            details.append({"installmentId": inst_id, "result": "dry_run", "amount": amount_mxn})
            charged += 1
            continue

        # Charge off-session
        try:
            if not stripe.api_key or stripe.api_key.startswith("sk_test_YOUR"):
                raise Exception("Stripe not configured — test mode")

            intent = stripe.PaymentIntent.create(
                amount=int(amount_mxn * 100),
                currency="mxn",
                payment_method=pm_id,
                confirm=True,
                off_session=True,
                description=f"Cuota automática préstamo — installment #{item.get('installmentNumber')}",
                metadata={
                    "installmentId": str(inst_id),
                    "loanId":        str(item.get("loanId")),
                    "companyId":     str(company_id),
                    "clientId":      str(client_id),
                    "lenderId":      str(lender_id),
                    "type":          "auto_repayment",
                },
            )

            log_integration("stripe", "payment_intent_offsession_charge",
                            response={"paymentIntentId": intent["id"], "amountMXN": amount_mxn})
            log_workflow_step("Installment Auto-Charged", workflow_name="money_trail", action="auto_repayment",
                              entity="loanInstallments", entity_id=inst_id,
                              message=f"${amount_mxn:,.2f} MXN cuota #{item.get('installmentNumber')} préstamo {item.get('loanId')}")

            _sp_installments({
                "action":                "update_status",
                "installmentId":         inst_id,
                "status":                "paid",
                "stripePaymentIntentId": intent["id"],
                "paidAt":                datetime.now(timezone.utc).isoformat(),
                "attemptCount":          attempts + 1,
            })

            try:
                from modules.rewardBenefits import award_on_time_payment
                award_on_time_payment(company_id, client_id, inst_id, amount_mxn)
            except Exception as _e:
                print(f"[rewards] puntos de cuota {inst_id} omitidos: {_e}")
            charged += 1
            transfer_note = None
            try:
                # Move the collected repayment from the platform's balance to
                # the lender's Connected Account — mirrors disburse_loan()'s
                # transfer-to-recipient pattern. Kept in its own try/except:
                # the borrower's charge already succeeded, so a lender-side
                # transfer hiccup shouldn't flip this installment to failed.
                lender_acct = _sp_connected_accounts({"action": "get", "clientId": lender_id, "companyId": company_id})
                lender_acct_id = lender_acct.get("connectedAccountId") if isinstance(lender_acct, dict) else None
                if lender_acct_id:
                    transfer = stripe.Transfer.create(
                        amount=int(amount_mxn * 100),
                        currency="mxn",
                        destination=lender_acct_id,
                        metadata={
                            "installmentId": str(inst_id),
                            "loanId":        str(item.get("loanId")),
                            "companyId":     str(company_id),
                            "lenderId":      str(lender_id),
                            "type":          "loan_repayment",
                        },
                    )
                    await credit_wallet({
                        "clientId": lender_id, "companyId": company_id,
                        "amountMXN": amount_mxn, "type": "repayment_received",
                    })
                    transfer_note = transfer["id"]
                else:
                    transfer_note = "no_lender_connected_account"
            except Exception as e:
                print(f"[automatedPayments] charge_due_installments: transfer-to-lender failed for installmentId={inst_id}: {e}")
                transfer_note = f"transfer_error: {e}"
            details.append({"installmentId": inst_id, "result": "charged", "intentId": intent["id"], "lenderTransfer": transfer_note})

        except stripe.error.CardError as e:
            # Card declined — increment attempt, will retry tomorrow
            _sp_installments({
                "action":        "update_status",
                "installmentId": inst_id,
                "status":        "failed",
                "failureReason": str(e),
                "lastAttemptAt": datetime.now(timezone.utc).isoformat(),
                "attemptCount":  attempts + 1,
            })
            failed += 1
            details.append({"installmentId": inst_id, "result": "card_declined", "error": str(e)})

        except Exception as e:
            failed += 1
            details.append({"installmentId": inst_id, "result": "error", "error": str(e)})

    return JSONResponse({
        "date":    today,
        "dryRun":  dry_run,
        "charged": charged,
        "failed":  failed,
        "skipped": skipped,
        "total":   len(due_items),
        "details": details,
    }, status_code=200)


# ── RFC-019: interés posterior al plazo (plan 'interest_free') ───────────────
#
# Un préstamo 'interest_free' se crea al 0 %: cuotas iguales de monto ÷ plazo.
# El capital que quede sin pagar al vencer la última cuota (M) genera
# loans.postTermRate (anual %), por día natural (actual/365), sin capitalizar,
# cobrado en una fila de loanInstallments por periodo mensual [M+(k-1)m, M+km).
# El periodo se cobra al corte, o antes si todo el capital quedó pagado.
# Las filas nunca se modifican; el job sólo registra un monto adeudado: no
# mueve ni confirma dinero (D1/D5). Se pagan por SPEI con confirmación humana.

POST_TERM_TYPE = "POST_TERM_INTEREST"
POST_TERM_GRACE_DAYS = 10      # fecha límite = corte + 10 días (RFC-019 Q1)
POST_TERM_DAY_BASIS = 365      # actual/365 (RFC-019 Q2)
_MAX_POST_TERM_PERIODS = 600   # tope de seguridad del ciclo (50 años)
_CENT = Decimal("0.01")


def _dec(value) -> Decimal:
    if value is None or value == "":
        return Decimal("0")
    return value if isinstance(value, Decimal) else Decimal(str(value))


def _to_date(value):
    """'YYYY-MM-DD' or ISO datetime → date (None if empty)."""
    if not value:
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, datetime):
        return value.date()
    return date.fromisoformat(str(value)[:10])


def _money(value: Decimal) -> Decimal:
    return value.quantize(_CENT, rounding=ROUND_HALF_UP)


def compute_post_term_interest(json_file: dict) -> dict:
    """
    Pure calculation (no DB). json_file: {
      "termMonths": int, "postTermRate": number (annual %),
      "installments": [loanInstallments rows: installmentNumber, installmentType,
                       dueDate, principal, interest, amount, status, paidAt],
      "asOfDate": "YYYY-MM-DD" (default: today)
    }
    Returns Decimals: termEndDate, unpaidPrincipal, billedInterest,
    billedUnpaidInterest, periodsDue (closed periods not billed yet),
    accruedUnbilledInterest (periodsDue + the open period so far),
    nextCutoffDate.
    """
    term_months = int(json_file.get("termMonths") or 0)
    rate = _dec(json_file.get("postTermRate"))
    as_of = _to_date(json_file.get("asOfDate")) or date.today()
    rows = json_file.get("installments") or []

    regular = [r for r in rows if (r.get("installmentType") or "REGULAR") != POST_TERM_TYPE]
    interest_rows = [r for r in rows if r.get("installmentType") == POST_TERM_TYPE]
    billed_numbers = {int(r.get("installmentNumber")) for r in interest_rows}
    billed = sum((_dec(r.get("interest")) for r in interest_rows), Decimal("0"))
    billed_unpaid = sum((_dec(r.get("interest")) for r in interest_rows if r.get("status") != "paid"), Decimal("0"))

    result = {
        "termEndDate": None, "unpaidPrincipal": Decimal("0"),
        "billedInterest": _money(billed), "billedUnpaidInterest": _money(billed_unpaid),
        "periodsDue": [], "accruedUnbilledInterest": Decimal("0.00"), "nextCutoffDate": None,
    }
    if not regular or term_months <= 0:
        return result

    last = next((r for r in regular if int(r.get("installmentNumber") or 0) == term_months), None)
    term_end = _to_date(last.get("dueDate")) if last else max(_to_date(r.get("dueDate")) for r in regular)
    result["termEndDate"] = term_end

    # (capital, fecha en que dejó de deberse | None si sigue sin pagar)
    debts = []
    for r in regular:
        paid_on = _to_date(r.get("paidAt")) if r.get("status") == "paid" else None
        if r.get("status") == "paid" and paid_on is None:
            paid_on = date.min  # pagada sin fecha: no genera interés
        debts.append((_dec(r.get("principal")), paid_on))

    def unpaid_at(day: date) -> Decimal:
        return sum((p for p, end in debts if end is None or end > day), Decimal("0"))

    result["unpaidPrincipal"] = _money(unpaid_at(as_of))
    if as_of <= term_end or rate <= 0:
        result["nextCutoffDate"] = term_end + relativedelta(months=1) if as_of <= term_end else None
        return result

    fully_paid_on = max(end for _, end in debts) if all(end is not None for _, end in debts) else None
    daily = rate / Decimal("100") / Decimal(POST_TERM_DAY_BASIS)
    pending_billing = Decimal("0")

    for k in range(1, _MAX_POST_TERM_PERIODS + 1):
        start = term_end + relativedelta(months=k - 1)
        cutoff = term_end + relativedelta(months=k)
        if fully_paid_on is not None and fully_paid_on <= start:
            break
        period_end = min(cutoff, fully_paid_on) if fully_paid_on is not None else cutoff
        window_end = min(period_end, as_of)

        accrued = Decimal("0")
        for principal, end in debts:
            stop = window_end if end is None else min(end, window_end)
            days = (stop - start).days
            if days > 0:
                accrued += principal * days * daily
        accrued = _money(accrued)

        if as_of >= period_end:  # periodo cerrado
            number = term_months + k
            if number not in billed_numbers and accrued > 0:
                result["periodsDue"].append({
                    "periodNumber": k,
                    "installmentNumber": number,
                    "interestPeriodStart": start,
                    "interestPeriodEnd": period_end,
                    "interest": accrued,
                    "remainingBalance": _money(unpaid_at(period_end)),
                    "dueDate": max(period_end, as_of) + relativedelta(days=POST_TERM_GRACE_DAYS),
                })
                pending_billing += accrued
            if fully_paid_on is not None and period_end == fully_paid_on:
                break
            continue

        result["nextCutoffDate"] = cutoff  # periodo en curso
        pending_billing += accrued
        break

    result["accruedUnbilledInterest"] = _money(pending_billing)
    return result


def _sp_installments_all(payload: dict) -> dict:
    """Like _sp_installments but joins every row (FOR JSON splits large results)."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanInstallments] @pjsonfile = %s",
            (json.dumps({"installments": [payload]}),)
        )
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    except Exception as e:
        print(f"[automatedPayments] installments SP error: {e}")
        return {"error": str(e)}
    finally:
        if conn:
            conn.close()


def _sp_loan_one(loan_id, company_id) -> dict:
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loans_one] @pjsonfile = %s",
            (json.dumps({"loans": [{"loanId": loan_id, "companyId": company_id}]}),)
        )
        row = cursor.fetchone()
        loans = (json.loads(row[0]) if row and row[0] else {}).get("loans", [])
        return loans[0] if loans else {}
    except Exception as e:
        print(f"[automatedPayments] sp_loans_one error loanId={loan_id}: {e}")
        return {}
    finally:
        if conn:
            conn.close()


def _iso(value):
    return value.isoformat() if isinstance(value, date) else value


async def accrue_post_term_interest(json_file: dict):
    """
    Daily job (and worker-key endpoint). Bills every closed post-term period
    of each active 'interest_free' loan as one immutable loanInstallments row.

    Body: { "companyId"?: int (omit = global sweep), "asOfDate"?: "YYYY-MM-DD", "dryRun"?: bool }
    Returns: { asOfDate, loans, created, skipped, dryRun, details: [...] }
    """
    as_of = _to_date(json_file.get("asOfDate")) or date.today()
    dry_run = bool(json_file.get("dryRun", False))
    query = {"action": "post_term_candidates", "asOfDate": as_of.isoformat()}
    if json_file.get("companyId"):
        query["companyId"] = int(json_file["companyId"])

    data = _sp_installments_all(query)
    if "error" in data:
        return JSONResponse({"error": data["error"]}, status_code=500)

    created = skipped = 0
    details = []
    candidates = data.get("loans", [])
    for loan in candidates:
        loan_id = loan.get("loanId")
        installments = loan.get("installments") or []
        calc = compute_post_term_interest({
            "termMonths": loan.get("termMonths"), "postTermRate": loan.get("postTermRate"),
            "installments": installments, "asOfDate": as_of.isoformat(),
        })
        parties = next((i for i in installments if i.get("clientId") and i.get("lenderId")), {})
        for period in calc["periodsDue"]:
            entry = {"loanId": loan_id, "installmentNumber": period["installmentNumber"],
                     "interest": float(period["interest"])}
            if dry_run:
                details.append({**entry, "result": "dry_run"})
                continue
            res = _sp_installments({
                "action": "insert_post_term_interest",
                "loanId": loan_id, "companyId": loan.get("companyId"),
                "clientId": parties.get("clientId"), "lenderId": parties.get("lenderId"),
                "installmentNumber": period["installmentNumber"],
                "dueDate": _iso(period["dueDate"]),
                "interest": str(period["interest"]),
                "remainingBalance": str(period["remainingBalance"]),
                "interestPeriodStart": _iso(period["interestPeriodStart"]),
                "interestPeriodEnd": _iso(period["interestPeriodEnd"]),
            })
            if res.get("created"):
                created += 1
                details.append({**entry, "result": "created", "installmentId": res.get("installmentId")})
                log_workflow_step("Post-term interest billed", workflow_name="money_trail",
                                  action="post_term_interest", entity="loanInstallments",
                                  entity_id=res.get("installmentId"),
                                  message=f"loanId={loan_id} periodo {period['periodNumber']}")
            else:
                skipped += 1
                details.append({**entry, "result": res.get("error") or ("already_billed" if res else "sp_error")})

    return JSONResponse({
        "asOfDate": as_of.isoformat(), "dryRun": dry_run, "loans": len(candidates),
        "created": created, "skipped": skipped, "details": details,
    }, status_code=200)


async def post_term_interest_status(json_file: dict):
    """
    Read-only summary for LoanDetailPage.

    Body: { "loanId": int, "companyId": int, "asOfDate"?: "YYYY-MM-DD" }
    Returns: { paymentPlan, postTermRate, termEndDate, unpaidPrincipal, billedInterest,
               billedUnpaidInterest, accruedUnbilledInterest, nextCutoffDate }
    """
    loan_id = json_file.get("loanId")
    company_id = json_file.get("companyId")
    if not loan_id or not company_id:
        return JSONResponse({"error": "loanId y companyId son obligatorios"}, status_code=400)

    loan = _sp_loan_one(loan_id, company_id)
    if not loan:
        return JSONResponse({"error": "Préstamo no encontrado"}, status_code=404)
    plan = loan.get("paymentPlan") or "standard"
    if plan != "interest_free":
        return JSONResponse({"loanId": loan_id, "paymentPlan": plan}, status_code=200)

    data = _sp_installments_all({"action": "list", "loanId": loan_id, "companyId": company_id})
    if "error" in data:
        return JSONResponse({"error": data["error"]}, status_code=500)

    calc = compute_post_term_interest({
        "termMonths": loan.get("termMonths"), "postTermRate": loan.get("postTermRate"),
        "installments": data.get("installments", []), "asOfDate": json_file.get("asOfDate"),
    })
    return JSONResponse({
        "loanId": loan_id,
        "paymentPlan": plan,
        "postTermRate": float(_dec(loan.get("postTermRate"))),
        "termEndDate": _iso(calc["termEndDate"]),
        "unpaidPrincipal": float(calc["unpaidPrincipal"]),
        "billedInterest": float(calc["billedInterest"]),
        "billedUnpaidInterest": float(calc["billedUnpaidInterest"]),
        "accruedUnbilledInterest": float(calc["accruedUnbilledInterest"]),
        "nextCutoffDate": _iso(calc["nextCutoffDate"]),
    }, status_code=200)
