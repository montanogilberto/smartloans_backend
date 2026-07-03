from fastapi import APIRouter
from modules.legalCases import legalCases_sp

router = APIRouter()

@router.post("/legalCases", summary="Legal Cases — loan recovery and juicio mercantil management",
    description="""
actions:
  open_case          — create a legal recovery case for a defaulted loan (push to lender + lawyer)
  assign_lawyer      — assign a registered lawyer to a case (push to both parties)
  get_expediente     — retrieve full digital expediente: contracts, pagarés, chats, payments, biometrics
  list_cases         — all cases (filter by lawyerId, lenderId, status)
  get_case           — single case detail by caseId
  update_status      — update case stage (open → demand_filed → judgment → embargo → closed)
  add_case_note      — lawyer adds a progress note to the case
  close_case         — mark case as resolved (push to lender and lawyer)
  embargo_executed   — record embargo execution and recovered amount (push auto-fired)

Body: { "case": [{ "action": "...", "companyId": int, "loanId": int, "caseId": int, ...fields }] }
""")
async def legalCases(json: dict):
    payload = json.get("case", [{}])[0] if isinstance(json.get("case"), list) else json
    return await legalCases_sp(payload)
