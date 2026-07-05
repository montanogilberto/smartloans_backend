from fastapi import APIRouter
from modules.digitalContracts import digitalContracts_sp

router = APIRouter()

@router.post("/digitalContracts", summary="Digital Contracts — contracts and pagarés management",
    description="""
actions:
  create_contract   — generate a digital loan contract + pagaré for a given loanId
  sign_contract     — record electronic signature from borrower or lender (push auto-fired)
  get_contract      — retrieve full contract details and signing status
  list_contracts    — all contracts for a client (borrower or lender)
  void_contract     — cancel a contract before both parties sign
  download_pdf      — get signed PDF URL for contract or pagaré

Body: { "contract": [{ "action": "...", "companyId": int, "loanId": int, "clientId": int, ...fields }] }
""")
async def digitalContracts(json: dict):
    payload = json.get("contract", [{}])[0] if isinstance(json.get("contract"), list) else json
    return await digitalContracts_sp(payload)
