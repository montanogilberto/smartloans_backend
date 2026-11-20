"""Lender platform fee — RFC-016 fase 3b (D10).

GMO Prestamos' own service fee: 5% of the loan principal + IVA 16%, paid ONLY by
the lender, by card on the platform's Stripe account, when the loan contract is
generated (the FUNDING paymentIntent is created) and BEFORE the lender sends the
SPEI. It is GMO's revenue for its service — never loan money: the loan still moves
only by direct SPEI lender -> borrower (D1, non-custodial).

Rules this module keeps:
  * Amounts are computed by sp_platformFees from loans.principalAmount — never here,
    never by the app.
  * Only Stripe marks a fee PAID or REFUNDED: the signed /stripe/webhook calls
    handle_fee_webhook_event(). There is no endpoint the app can call to set a status.
  * One fee per loan, one Stripe charge per loan (idempotency key per loan).
  * Not disbursed yet -> refund in full, automatically (expiry cron, cancellation).
    Disbursed (CONFIRMED fundingTransaction) -> never refunded; the SP enforces it.
  * Funding stays locked until the fee is PAID (require_fee_paid), when
    PLATFORM_FEE_ENFORCED=true. Off by default so loans signed before the rollout
    keep working.
  * Nothing is charged unless PLATFORM_FEE_CHARGE_ENABLED=true (off by default):
    the app must first ship the fee-card and 3-D Secure screens, so no lender is
    charged without seeing why. Refunds and webhooks always run.
  * Logs carry ids and statuses only — never card data, client_secret or amounts
    tied to a person's name.

Hand-written: payments-domain exception to the factory pipeline (global CLAUDE.md §3).
Table + SPs come from the factory PRD tests/prd_platformFee.json.
"""
import json
import logging
import os
from decimal import Decimal, ROUND_HALF_UP

import stripe
from fastapi.responses import JSONResponse

from databases import connection
from modules.loanPush import push_in_background
from observability.logger import log_integration, log_workflow_step

logger = logging.getLogger(__name__)

stripe.api_key = stripe.api_key or os.getenv("STRIPE_SECRET_KEY", "")

FEE_TYPE = "platform_fee"          # PaymentIntent metadata.type
WORKFLOW = "platform_fee"
CARD_PURPOSE = "platform_fee_card"  # SetupIntent / Customer metadata


def _stripe_ready() -> bool:
    key = stripe.api_key or ""
    return bool(key) and not key.startswith("sk_test_YOUR")


def _flag(name: str) -> bool:
    return os.getenv(name, "").strip().lower() in ("1", "true")


def fee_enforced() -> bool:
    return _flag("PLATFORM_FEE_ENFORCED")


def charging_enabled() -> bool:
    """Kill switch: no fee is created or charged until this is on."""
    return _flag("PLATFORM_FEE_CHARGE_ENABLED")


# ── sp_platformFees ──────────────────────────────────────────────────────────

def _exec(payload: dict) -> list:
    """First result set of sp_platformFees as a list of tuples."""
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_platformFees] @pjsonfile = %s",
                       (json.dumps({"platformFees": [payload]}),))
        return [tuple(r) for r in cursor.fetchall()] if cursor.description else []
    finally:
        if conn:
            conn.close()


def _sp_status(payload: dict) -> dict:
    """Write actions answer one row (value, msg, error)."""
    rows = _exec(payload)
    if not rows:
        return {"value": "", "msg": "no result", "error": "1"}
    value, msg, error = (list(rows[0]) + ["", "", ""])[:3]
    return {"value": value or "", "msg": msg or "", "error": error or ""}


def _sp_fees(payload: dict) -> list:
    """by_loan / request_refund answer one JSON value {platformFees:[...]} — or the
    (value, msg, error) row when they refuse. Money parses as Decimal."""
    rows = _exec(payload)
    if not rows:
        return []
    first = rows[0]
    if len(first) >= 3:  # status row: refused (e.g. already disbursed)
        raise FeeError(first[1] or "Operación rechazada")
    raw = "".join(r[0] for r in rows if r and r[0])
    data = json.loads(raw, parse_float=Decimal) if raw else {}
    return data.get("platformFees") or []


class FeeError(Exception):
    pass


def fee_for_loan(company_id, loan_id) -> dict | None:
    fees = _sp_fees({"action": "by_loan", "companyId": int(company_id), "loanId": int(loan_id)})
    return fees[0] if fees else None


def _centavos(total) -> int:
    return int((Decimal(str(total)) * 100).to_integral_value(rounding=ROUND_HALF_UP))


# ── Lender card (saved once, on a Customer so it can be charged later) ───────

def _fee_customer(client_id: int, company_id: int) -> str:
    """The lender's Customer for fee cards on the platform account. A card saved
    without a Customer can't be reused off-session, so the fee card always has one."""
    query = (f"metadata['clientId']:'{int(client_id)}' AND metadata['feeCompanyId']:'{int(company_id)}'"
             f" AND metadata['purpose']:'{CARD_PURPOSE}'")
    found = stripe.Customer.search(query=query, limit=1)
    if found["data"]:
        return found["data"][0]["id"]
    return stripe.Customer.create(
        metadata={"clientId": str(int(client_id)), "feeCompanyId": str(int(company_id)), "purpose": CARD_PURPOSE},
        idempotency_key=f"fee-customer-{int(company_id)}-{int(client_id)}",
    )["id"]


async def create_fee_card_setup_intent(payload: dict, session_client_id: int):
    """POST /platformFees/card/setup-intent — SetupIntent for the lender's fee card.
    The app confirms it with Stripe.js and then calls /automated-payments/save-method
    (which stores the card in savedPaymentMethods, as for any saved card)."""
    client_id, company_id = payload.get("clientId"), payload.get("companyId")
    if not client_id or not company_id:
        return JSONResponse({"error": "clientId y companyId son requeridos"}, status_code=400)
    if int(client_id) != int(session_client_id):
        return JSONResponse({"error": "Forbidden"}, status_code=403)
    if not _stripe_ready():
        return JSONResponse({"error": "Los pagos no están configurados."}, status_code=503)
    try:
        customer = _fee_customer(int(client_id), int(company_id))
        si = stripe.SetupIntent.create(
            customer=customer, usage="off_session", payment_method_types=["card"],
            metadata={"clientId": str(client_id), "companyId": str(company_id), "purpose": CARD_PURPOSE},
        )
        log_integration("stripe", "fee_card_setup_intent", response={"setupIntentId": si["id"]})
        return JSONResponse({"clientSecret": si["client_secret"], "setupIntentId": si["id"]}, status_code=200)
    except stripe.StripeError as e:
        logger.warning("[platformFees] setup-intent clientId=%s failed: %s", client_id, type(e).__name__)
        return JSONResponse({"error": "No se pudo preparar el registro de la tarjeta."}, status_code=400)


def _lender_card(company_id: int, client_id: int) -> tuple[str, str] | None:
    """(paymentMethodId, customerId) of the lender's saved card, if it can be
    charged off-session (attached to a Customer)."""
    from modules.automatedPayments import _sp_saved_methods
    saved = _sp_saved_methods({"action": "get", "clientId": client_id, "companyId": company_id}) or {}
    pm_id = saved.get("stripePaymentMethodId")
    if not pm_id or pm_id.startswith("pm_mock"):
        return None
    pm = stripe.PaymentMethod.retrieve(pm_id)
    customer = pm["customer"]
    return (pm_id, customer) if customer else None


# ── Charge ───────────────────────────────────────────────────────────────────

def charge_fee(company_id, loan_id, lender_client_id) -> dict:
    """Create the loan's fee (if missing) and charge the lender's saved card.
    Idempotent per loan. Never marks PAID: the webhook does. Returns the fee row."""
    if not charging_enabled():
        raise FeeError("El cobro de la comisión aún no está activo.")
    company_id, loan_id, lender_client_id = int(company_id), int(loan_id), int(lender_client_id)
    fee = fee_for_loan(company_id, loan_id)
    if fee is None:
        res = _sp_status({"action": "insert", "companyId": company_id, "loanId": loan_id,
                          "lenderClientId": lender_client_id, "reason": "contract generated"})
        if res["error"]:
            raise FeeError(res["msg"])
        fee = fee_for_loan(company_id, loan_id)
        log_workflow_step("Platform Fee Created", workflow_name=WORKFLOW, entity="platformFees",
                          entity_id=fee and fee.get("platformFeeId"), message=f"loan {loan_id}")
    if fee["status"] not in ("PENDING", "FAILED"):
        return fee
    if int(fee["lenderClientId"]) != lender_client_id:
        raise FeeError("La comisión pertenece a otro prestamista.")
    if fee.get("stripePaymentIntentId"):
        # Already charged once: the lender finishes it in the app (3-D Secure or
        # another card) with the same PaymentIntent — never a second charge.
        return fee
    if not _stripe_ready():
        raise FeeError("Los pagos no están configurados.")

    card = _lender_card(company_id, lender_client_id)
    if card is None:
        _sp_status({"action": "update", "platformFeeId": fee["platformFeeId"], "companyId": company_id,
                    "failureReason": "Sin tarjeta registrada para la comisión"})
        push_in_background(company_id, lender_client_id, "platform_fee_card_needed",
                           amount=fee["totalAmount"], loanId=loan_id)
        return fee_for_loan(company_id, loan_id)
    pm_id, customer = card

    failure, intent_id = None, None
    try:
        intent = stripe.PaymentIntent.create(
            amount=_centavos(fee["totalAmount"]), currency="mxn",
            customer=customer, payment_method=pm_id, off_session=True, confirm=True,
            description=f"Comisión GMO Prestamos — préstamo #{loan_id}",
            metadata={"type": FEE_TYPE, "platformFeeId": str(fee["platformFeeId"]), "loanId": str(loan_id),
                      "lenderClientId": str(lender_client_id), "companyId": str(company_id)},
            idempotency_key=f"platform_fee:{company_id}:{loan_id}",
        )
        intent_id = intent["id"]
    except stripe.CardError as e:
        # Declined or needs 3-D Secure: Stripe still created the PaymentIntent.
        pi = getattr(getattr(e, "error", None), "payment_intent", None)
        intent_id = pi["id"] if pi else None
        failure = "authentication_required" if e.code == "authentication_required" else (e.code or "card_declined")
    log_integration("stripe", "platform_fee_charge",
                    response={"platformFeeId": fee["platformFeeId"], "paymentIntentId": intent_id, "failure": failure})

    if intent_id:
        stored = _sp_status({"action": "set_intent", "platformFeeId": fee["platformFeeId"], "companyId": company_id,
                             "stripePaymentIntentId": intent_id, "failureReason": failure})
        if stored["error"]:
            logger.error("[platformFees] set_intent loan=%s pi=%s: %s", loan_id, intent_id, stored["msg"])
    if failure:
        push_in_background(company_id, lender_client_id, "platform_fee_action_required",
                           amount=fee["totalAmount"], loanId=loan_id)
    return fee_for_loan(company_id, loan_id)


def charge_fee_in_background(company_id, loan_id, lender_client_id) -> None:
    """Fire-and-forget from the contract/funding flow: a fee problem never fails it."""
    import threading

    if not charging_enabled():
        logger.info("[platformFees] charging off (PLATFORM_FEE_CHARGE_ENABLED): loan=%s not charged", loan_id)
        return

    def run():
        try:
            charge_fee(company_id, loan_id, lender_client_id)
        except Exception as e:
            logger.error("[platformFees] charge loan=%s failed: %s", loan_id, e)
    threading.Thread(target=run, daemon=True).start()


async def retry_fee(payload: dict, session_client_id: int):
    """POST /platformFees/retry — the lender added a card: charge again (first
    attempt only creates the PaymentIntent once; a later retry returns it)."""
    company_id, loan_id = payload.get("companyId"), payload.get("loanId")
    if not company_id or not loan_id:
        return JSONResponse({"error": "companyId y loanId son requeridos"}, status_code=400)
    try:
        fee = charge_fee(company_id, loan_id, session_client_id)
        return JSONResponse(_public(fee), status_code=200)
    except FeeError as e:
        return JSONResponse({"error": str(e)}, status_code=400)
    except stripe.StripeError as e:
        logger.warning("[platformFees] retry loan=%s: %s", loan_id, type(e).__name__)
        return JSONResponse({"error": "No se pudo cobrar la comisión."}, status_code=400)


async def fee_client_secret(payload: dict, session_client_id: int):
    """POST /platformFees/client-secret — the lender's OWN pending fee only:
    the PaymentIntent client_secret so the app confirms it on-session (3-D Secure,
    or another card). Never changes a status."""
    company_id, loan_id = payload.get("companyId"), payload.get("loanId")
    if not company_id or not loan_id:
        return JSONResponse({"error": "companyId y loanId son requeridos"}, status_code=400)
    fee = fee_for_loan(company_id, loan_id)
    if not fee or int(fee["lenderClientId"]) != int(session_client_id):
        return JSONResponse({"error": "Comisión no encontrada"}, status_code=404)
    if fee["status"] not in ("PENDING", "FAILED") or not fee.get("stripePaymentIntentId"):
        return JSONResponse({"error": "Esta comisión no tiene un pago pendiente."}, status_code=409)
    intent = stripe.PaymentIntent.retrieve(fee["stripePaymentIntentId"])
    meta = intent["metadata"]
    if meta.get("type") != FEE_TYPE or meta.get("loanId") != str(loan_id):
        return JSONResponse({"error": "Pago no válido"}, status_code=400)
    return JSONResponse({"clientSecret": intent["client_secret"], **_public(fee)}, status_code=200)


async def get_fee(payload: dict, session_client_id: int):
    """POST /platformFees/by-loan — the lender's own fee for a loan (status screen)."""
    fee = fee_for_loan(payload.get("companyId"), payload.get("loanId")) if payload.get("loanId") else None
    if not fee or int(fee["lenderClientId"]) != int(session_client_id):
        return JSONResponse({"platformFee": None}, status_code=200)
    return JSONResponse({"platformFee": _public(fee)}, status_code=200)


def _public(fee: dict | None) -> dict:
    """What the app may see: amounts and status, never Stripe ids."""
    if not fee:
        return {}
    keys = ("platformFeeId", "loanId", "baseAmount", "feeRateBps", "feeAmount", "ivaRateBps", "ivaAmount",
            "totalAmount", "currency", "status", "failureReason", "paidAt", "refundedAt")
    return {k: (str(fee[k]) if isinstance(fee.get(k), Decimal) else fee.get(k)) for k in keys}


# ── Webhook (called only from the signature-verified /stripe/webhook) ────────

async def handle_fee_webhook_event(event_type: str, obj: dict) -> None:
    """payment_intent.succeeded / payment_intent.payment_failed with
    metadata.type=platform_fee, and charge.refunded for a fee charge."""
    if event_type == "charge.refunded":
        if obj.get("refunded") is not True:  # partial refund: the fee is not refunded
            return
        intent_id = obj.get("payment_intent")
        meta = obj.get("metadata") or {}
        new_status, extra = "REFUNDED", {}
        refunds = (obj.get("refunds") or {}).get("data") or []
        if refunds:
            extra["stripeRefundId"] = refunds[0].get("id")
    else:
        intent_id = obj.get("id")
        meta = obj.get("metadata") or {}
        if event_type == "payment_intent.succeeded":
            new_status, extra = "PAID", {}
        else:
            new_status = "FAILED"
            extra = {"failureReason": ((obj.get("last_payment_error") or {}).get("code") or "payment_failed")[:300]}
    if not intent_id:
        return

    res = _sp_status({"action": "mark_webhook", "stripePaymentIntentId": intent_id, "status": new_status, **extra})
    company_id, loan_id, client_id = meta.get("companyId"), meta.get("loanId"), meta.get("lenderClientId")
    log_workflow_step("Platform Fee Webhook", workflow_name=WORKFLOW, entity="platformFees",
                      message=f"pi {intent_id} -> {new_status} ({res['error'] and res['msg'] or 'ok'})")

    if res["error"]:
        # A charge that succeeded on a fee already cancelled before any charge
        # (cancel raced the bank): give the money back, it is not GMO's.
        if new_status == "PAID" and res["value"] == "REFUNDED":
            try:
                stripe.Refund.create(payment_intent=intent_id, reason="duplicate",
                                     metadata={"type": FEE_TYPE, "loanId": str(loan_id)},
                                     idempotency_key=f"platform_fee_late_refund:{intent_id}")
                logger.warning("[platformFees] pi=%s succeeded after the fee was cancelled: refunded", intent_id)
            except stripe.InvalidRequestError as e:
                # Re-delivered 'succeeded' for a charge refunded the normal way.
                if getattr(e, "code", None) != "charge_already_refunded":
                    raise
        return

    template = {"PAID": "platform_fee_paid", "FAILED": "platform_fee_action_required",
                "REFUNDED": "platform_fee_refunded"}.get(new_status)
    if template and company_id and client_id and res["value"]:
        fee = fee_for_loan(company_id, loan_id) if loan_id else None
        push_in_background(company_id, client_id, template,
                           amount=fee and fee["totalAmount"], loanId=loan_id)


# ── Refund (loan not disbursed) ──────────────────────────────────────────────

def refund_fee(company_id, loan_id, reason: str) -> dict | None:
    """Full refund while the loan is NOT disbursed. sp_platformFees request_refund
    refuses once a CONFIRMED fundingTransaction exists. PAID -> Stripe Refund
    (REFUND_PENDING until charge.refunded); PENDING/FAILED -> cancel the
    PaymentIntent (nothing was charged) and the fee is REFUNDED right away."""
    try:
        # companyId may be None (expiry cron only knows the loanId): the SP takes
        # it from the fee row — loanId is the loans table's identity, unique.
        fees = _sp_fees({"action": "request_refund", "companyId": company_id and int(company_id),
                         "loanId": int(loan_id), "reason": (reason or "")[:300]})
    except FeeError as e:
        logger.info("[platformFees] refund loan=%s refused: %s", loan_id, e)
        return None
    if not fees:
        return None
    fee = fees[0]
    intent_id = fee.get("stripePaymentIntentId") or ""
    if intent_id and _stripe_ready():
        if fee["previousStatus"] == "PAID":
            refund = stripe.Refund.create(payment_intent=intent_id, reason="requested_by_customer",
                                          metadata={"type": FEE_TYPE, "loanId": str(loan_id)},
                                          idempotency_key=f"platform_fee_refund:{company_id}:{loan_id}")
            log_integration("stripe", "platform_fee_refund", response={"refundId": refund["id"], "loanId": loan_id})
        else:
            intent = stripe.PaymentIntent.retrieve(intent_id)
            if intent["status"] in ("requires_payment_method", "requires_confirmation", "requires_action"):
                stripe.PaymentIntent.cancel(intent_id)
            # If it already succeeded, the late 'succeeded' webhook refunds it.
    push_in_background(company_id, fee.get("lenderClientId"), "platform_fee_refunded_requested",
                       loanId=loan_id)
    return fee


def refund_fees_for_expired(expired: list) -> None:
    """From the paymentIntents expire_due cron: [{paymentIntentId, loanId}, ...]."""
    for item in expired or []:
        loan_id = item.get("loanId")
        if not loan_id:
            continue
        try:
            refund_fee(item.get("companyId"), loan_id, "Fondeo expirado")
        except Exception as e:
            logger.error("[platformFees] expiry refund loan=%s failed: %s", loan_id, e)


# ── Funding lock ─────────────────────────────────────────────────────────────

def require_fee_paid(company_id, loan_id) -> str | None:
    """None when funding may proceed for this loan; else the message to return.
    With PLATFORM_FEE_ENFORCED off, only an existing unpaid fee blocks."""
    if not company_id or not loan_id:
        return None
    try:
        fee = fee_for_loan(company_id, loan_id)
    except Exception as e:
        logger.error("[platformFees] fee check loan=%s failed: %s", loan_id, e)
        return "No se pudo verificar la comisión de la plataforma." if fee_enforced() else None
    if fee is None:
        # With charging off no fee is ever created: a missing fee can't block
        # funding then, or enforcement would lock every new loan for good.
        return "La comisión de la plataforma no está pagada." if fee_enforced() and charging_enabled() else None
    return None if fee["status"] == "PAID" else "La comisión de la plataforma no está pagada."


# ── Admin reads (sp_platformFees_all / _one) ─────────────────────────────────

def _read(sp_name: str, json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{sp_name}] @pjsonfile = %s", (json.dumps(json_file),))
        raw = "".join(r[0] for r in cursor.fetchall() if r and r[0]) if cursor.description else ""
        return JSONResponse(content=json.loads(raw) if raw else {"platformFees": []}, status_code=200)
    except Exception as e:
        logger.error("[platformFees] %s failed: %s", sp_name, e)
        return JSONResponse(content={"error": "No se pudieron leer las comisiones."}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_fees(json_file: dict):
    return _read("sp_platformFees_all", json_file)


def one_fee(json_file: dict):
    return _read("sp_platformFees_one", json_file)
