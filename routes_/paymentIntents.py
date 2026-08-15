from fastapi import APIRouter
from modules.paymentIntents import payment_intents_sp

router = APIRouter()


@router.post(
    "/paymentIntents",
    summary="Payment Intents — non-custodial funding/payment expectations",
    description="""
Records the EXPECTATION of a direct SPEI transfer between two clients — never
moves money. See sql/sp_paymentIntents.sql and docs/rfcs/RFC-003-payment-intents.md.

action "create":
  { "paymentIntents": [{ "action": "create", "companyId": int, "loanId": int,
    "installmentId"?: int, "intentType": "FUNDING"|"INSTALLMENT"|"PARTIAL"|"PAYOFF",
    "expectedAmountMXN": float, "payerClientId": int, "payeeClientId": int,
    "beneficiarySnapshotId": int, "suggestedReference": str, "expiresAt"?: str }] }

action "expire_due" (cron): { "paymentIntents": [{ "action": "expire_due", "companyId"?: int }] }
action "cancel": { "paymentIntents": [{ "action": "cancel", "companyId": int, "paymentIntentId": int }] }
action "list": { "paymentIntents": [{ "action": "list", "companyId": int, "loanId": int }] }
""",
)
def payment_intents(json: dict):
    return payment_intents_sp(json)
