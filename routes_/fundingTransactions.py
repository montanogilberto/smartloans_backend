from fastapi import APIRouter
from modules.fundingTransactions import funding_transactions_sp

router = APIRouter()


@router.post(
    "/fundingTransactions",
    summary="Funding Transactions — lender declares direct SPEI, borrower confirms",
    description="""
Non-custodial loan funding (RFC-002). The lender sends SPEI directly to the
borrower's CLABE from their own bank, then declares it here; the borrower
confirms or rejects. SmartLoans never initiates or holds the transfer.
See sql/sp_fundingTransactions.sql.

action "declare" (lender): { "fundingTransactions": [{ "action": "declare",
  "companyId": int, "loanId": int, "intentId": int, "lenderClientId": int,
  "borrowerClientId": int, "amountMXN": float, "transferDate": str }] }
  Requires an OPEN paymentIntent (intentType=FUNDING) for this loan/lender/borrower.

action "confirm" (borrower only): { "fundingTransactions": [{ "action": "confirm",
  "companyId": int, "fundingTransactionId": int, "confirmedByClientId": int }] }

action "reject" (borrower only): { "fundingTransactions": [{ "action": "reject",
  "companyId": int, "fundingTransactionId": int, "rejectedByClientId": int,
  "rejectReason": str }] }

action "escalate_due" (cron): { "fundingTransactions": [{ "action": "escalate_due",
  "companyId"?: int, "escalateAfterDays"?: int }] }

action "resolve_escalation" (support/admin only): { "fundingTransactions": [{
  "action": "resolve_escalation", "companyId": int, "fundingTransactionId": int,
  "resolution": "CONFIRMED"|"CANCELLED" }] }

action "list": { "fundingTransactions": [{ "action": "list", "companyId": int, "loanId"?: int }] }
action "one": { "fundingTransactions": [{ "action": "one", "companyId": int, "fundingTransactionId": int }] }
""",
)
def funding_transactions(json: dict):
    return funding_transactions_sp(json)
