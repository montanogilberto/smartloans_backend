from fastapi import APIRouter
from modules.clientCapabilities import client_capabilities_sp

router = APIRouter()


@router.post(
    "/clientCapabilities",
    summary="Client capabilities CRUD ('clientTypes' — which GMO applications a client participates in)",
    description="""action 0 (default) — read: { "clientCapabilities": [{ "companyId": int, "clientId"?: int, "capability"?: str }] }
action 1 — grant (insert if absent, reactivate if previously revoked):
  { "clientCapabilities": [{ "action": 1, "companyId": int, "clientId": int,
    "capability": "POS|SMARTLOANS_LENDER|SMARTLOANS_BORROWER|SMARTLOANS_JURIDICAL|REWARDS|ARCADE" }] }
action 2 — revoke (soft: isActive=0, never deletes the row):
  { "clientCapabilities": [{ "action": 2, "companyId": int, "clientId": int, "capability": str }] }
Separate from and does not read/write dbo.clients.clientType.""",
)
def client_capabilities(json: dict):
    return client_capabilities_sp(json)
