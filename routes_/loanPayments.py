from fastapi import APIRouter
from modules.loanPayments import loanPayments_sp


router = APIRouter()


@router.post(
    "/loanPayments",
    summary="Loan Payments — action routing",
    description="""
actions:
  declare             — Borrower declares an SPEI payment with clave de rastreo and optional evidence.
  confirm             — Lender confirms reception of a PENDING_CONFIRMATION payment.
  reject              — Lender rejects a PENDING_CONFIRMATION payment with a reason.
  cancel              — Borrower cancels a PENDING_CONFIRMATION payment (e.g., typo).
  escalate_due        — System (cron) escalates overdue PENDING_CONFIRMATION payments to support.
  resolve_escalation  — Support resolves an ESCALATED payment (confirm or reject).
  list                — Retrieve a list of loan payments, optionally filtered by loanId, payeeClientId, or status.
  one                 — Retrieve a single loan payment by loanPaymentId.
  statement           — Get loan statement details (next/overdue installments, payoff amount, beneficiary).

Body: { "loanPayments": [{ "action": "...", "companyId": int, ...action fields }] }
"""
)
async def loanPayments(json: dict):
    payload = json.get("loanPayments", [{}])[0] if isinstance(json.get("loanPayments"), list) else json
    return await loanPayments_sp(payload)
