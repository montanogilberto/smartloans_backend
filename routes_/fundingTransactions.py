from fastapi import APIRouter
from modules.fundingTransactions import (
    funding_transactions_sp,
    funding_transactions_confirm,
    funding_transactions_resolve_escalation,
)

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
  "borrowerClientId": int, "amountMXN": float, "transferDate": str,
  "actorUserId"?: int }] }
  Requires an OPEN paymentIntent (intentType=FUNDING) for this loan/lender/borrower.

action "confirm" (borrower only): { "fundingTransactions": [{ "action": "confirm",
  "companyId": int, "fundingTransactionId": int, "confirmedByClientId": int,
  "actorUserId"?: int }] }
  Orchestrates: confirm -> sp_loans transition (pending_funding->funded) ->
  PaymentSchedule generation -> sp_loans transition (funded->active) if the
  schedule succeeds. Response includes "loanStatus" ("funded" or "active")
  and an optional "warning" if the loan couldn't reach "active" automatically
  (stays "funded", needs manual follow-up) — the funding confirmation itself
  always succeeds independently of that.

action "reject" (borrower only): { "fundingTransactions": [{ "action": "reject",
  "companyId": int, "fundingTransactionId": int, "rejectedByClientId": int,
  "rejectReason": str, "actorUserId"?: int }] }

action "escalate_due" (cron): { "fundingTransactions": [{ "action": "escalate_due",
  "companyId"?: int, "escalateAfterDays"?: int }] }

action "resolve_escalation" (support/admin only — enforced here via
dbo.userCompanies.roleName, not inside the SP): { "fundingTransactions": [{
  "action": "resolve_escalation", "companyId": int, "fundingTransactionId": int,
  "resolution": "CONFIRMED"|"CANCELLED", "resolverUserId": int,
  "resolutionNote"?: str }] }

action "list": { "fundingTransactions": [{ "action": "list", "companyId": int, "loanId"?: int }] }
action "one": { "fundingTransactions": [{ "action": "one", "companyId": int, "fundingTransactionId": int }] }
""",
)
async def funding_transactions(json: dict):
    action = ((json.get("fundingTransactions") or [{}])[0]).get("action")
    if action == "confirm":
        return await funding_transactions_confirm(json)
    if action == "resolve_escalation":
        return await funding_transactions_resolve_escalation(json)
    return funding_transactions_sp(json)
