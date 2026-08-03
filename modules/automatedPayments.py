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
from dateutil.relativedelta import relativedelta
from modules.stripe_payments import _sp_connected_accounts
from modules.walletBalance import credit_wallet

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

    company_id  = int(payload.get("companyId", 0))
    loan_id     = int(payload.get("loanId", 0))
    inst_id     = int(payload.get("installmentId", 0))
    borrower_id = int(payload.get("clientId", 0))
    if not (company_id and loan_id and inst_id and borrower_id):
        return JSONResponse({"error": "companyId, loanId, installmentId y clientId son requeridos"}, status_code=400)

    # The SP's 'list' action omits clientId/lenderId — read the row directly
    # for ownership + counterpart (read-only; mutations stay in the SP).
    conn = _conn()
    cur = conn.cursor()
    cur.execute(
        "SELECT clientId, lenderId, installmentNumber, amount, principal, interest, status, attemptCount "
        "FROM loanInstallments WHERE installmentId = %s AND loanId = %s AND companyId = %s",
        (inst_id, loan_id, company_id))
    row = cur.fetchone()
    conn.close()
    if not row:
        return JSONResponse({"error": f"Cuota {inst_id} no encontrada en el préstamo {loan_id}"}, status_code=404)
    inst_client_id, lender_id, inst_number = int(row[0]), int(row[1]), int(row[2])
    amount, principal, interest = float(row[3]), float(row[4] or 0), float(row[5] or 0)
    inst_status, attempt_count = row[6], int(row[7] or 0)
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

    try:
        # Hub tags are user_{userId}; lender_id is a CLIENT id — resolve first
        # or the push targets an empty tag and vanishes silently.
        conn = _conn()
        cur = conn.cursor()
        cur.execute("SELECT TOP 1 userId FROM users WHERE clientId = %s", (lender_id,))
        row = cur.fetchone()
        conn.close()
        if row:
            await send_azure_push(
                "💵 Cuota recibida",
                f"Cuota #{inst.get('installmentNumber')} de ${amount:,.2f} pagada por SPEI.",
                row[0],
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

            _sp_installments({
                "action":                "update_status",
                "installmentId":         inst_id,
                "status":                "paid",
                "stripePaymentIntentId": intent["id"],
                "paidAt":                datetime.now(timezone.utc).isoformat(),
                "attemptCount":          attempts + 1,
            })
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
