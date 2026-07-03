from fastapi import APIRouter
from modules.disbursement import disbursement_sp

router = APIRouter()

@router.post("/disbursement", summary="Disbursement — loan transfer tracking",
    description="""
actions:
  initiate          — lender initiates disbursement after signing contract (push to lender)
  confirm_sent      — lender confirms transfer was made (push to borrower)
  confirm_received  — borrower confirms receipt; loan status → active (push to both)
  get_status        — current disbursement status for a loanId
  list_disbursements — all disbursements for a client or lender
  failed            — mark disbursement as failed with error note (push to both)

Body: { "disbursement": [{ "action": "...", "companyId": int, "loanId": int, "clientId": int, ...fields }] }
""")
async def disbursement(json: dict):
    payload = json.get("disbursement", [{}])[0] if isinstance(json.get("disbursement"), list) else json
    return await disbursement_sp(payload)
