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
import stripe
from fastapi.responses import JSONResponse
from databases import connection
from datetime import datetime, timezone, date
from dateutil.relativedelta import relativedelta

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
        pm_id = si.get("payment_method")
        if not pm_id:
            return JSONResponse({"error": "SetupIntent has no payment method attached"}, status_code=400)

        pm = stripe.PaymentMethod.retrieve(pm_id)
        card = pm.get("card", {})

        result = _sp_saved_methods({
            "action": "upsert",
            "clientId": client_id,
            "companyId": company_id,
            "stripePaymentMethodId": pm_id,
            "last4":       card.get("last4", ""),
            "brand":       card.get("brand", ""),
            "expiryMonth": card.get("exp_month"),
            "expiryYear":  card.get("exp_year"),
        })

        return JSONResponse({"paymentMethod": result}, status_code=200)

    except stripe.StripeError as e:
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


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
            details.append({"installmentId": inst_id, "result": "charged", "intentId": intent["id"]})

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
