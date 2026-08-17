from fastapi import APIRouter
from modules.paymentHistory import payment_history_all_sp

router = APIRouter()


@router.post(
    "/all_paymentHistory",
    summary="Payment History — append-only audit trail (D16)",
    description="""
Read-only. Every status transition on fundingTransactions (and, once RFC-003's
loanPayments lands, on that table too) writes one row here in the same
transaction — see sql/sp_fundingTransactions.sql. Never UPDATE/DELETE.

Body: { "paymentHistory": [{ "companyId": int, "subjectType"?: "FUNDING"|"PAYMENT",
  "subjectId"?: int }] }
Returns: PaymentHistory[] ordered oldest-first (chronological read).
""",
)
def all_payment_history(json: dict):
    return payment_history_all_sp(json)
