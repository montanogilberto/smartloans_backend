from fastapi import APIRouter
from modules.transferEvidence import transfer_evidence_sp, upload_transfer_evidence_connector

router = APIRouter()


@router.post(
    "/transferEvidence/upload-image",
    summary="Upload a comprobante (SPEI transfer receipt) photo",
    tags=["connector"],
)
async def upload_transfer_evidence(json: dict):
    return await upload_transfer_evidence_connector(json)


@router.post(
    "/transferEvidence",
    summary="Transfer Evidence — structured proof of a direct SPEI transfer",
    description="""
Structured proof (clave de rastreo + bank + amount + optional attachment/hash)
attached to a fundingTransactions or (future) loanPayments declaration.
See sql/sp_transferEvidence.sql, RFC-002 §3, RFC-003 §3/§6.

action "create": { "transferEvidence": [{ "action": "create", "companyId": int,
  "referenceType": "FUNDING"|"INSTALLMENT"|"PARTIAL"|"PAYOFF", "referenceId": int,
  "claveRastreo": str, "transferDate": str, "bankFrom"?: str, "amountMXN": float,
  "evidenceFileUrl"?: str, "evidenceHash"?: str, "uploadedByClientId": int }] }
  FUNDING is fully validated: referenceId must be a PENDING_CONFIRMATION
  fundingTransactions row, and amountMXN must be within +/-$1 of the linked
  paymentIntent's expectedAmountMXN. Rate-limited to 5/day per reference.

action "list": { "transferEvidence": [{ "action": "list", "companyId": int,
  "referenceType"?: str, "referenceId"?: int }] }
action "one": { "transferEvidence": [{ "action": "one", "companyId": int, "transferEvidenceId": int }] }

action "validate": { "transferEvidence": [{ "action": "validate", "companyId": int,
  "transferEvidenceId": int, "validationStatus": "VALID"|"NEEDS_REVIEW"|"INVALID",
  "aiConfidence"?: float, "aiReasoning"?: str, "aiMismatches"?: str }] }
  Persists the evidence_validation_agent's verdict (LoanAgents_SmartLoans
  POST /validate-transfer-evidence) onto the row. Advisory only -- never
  touches fundingTransactions/loans status; the borrower's own confirmFunding
  still activates the loan.
""",
)
def transfer_evidence(json: dict):
    return transfer_evidence_sp(json)
