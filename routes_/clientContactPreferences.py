from fastapi import APIRouter
from modules.clientContactPreferences import (
    clientContactPreferences_sp, all_clientContactPreferences_sp, one_clientContactPreferences_sp
)

router = APIRouter()

# The WhatsApp BAJA/ALTA keyword has no route on purpose: only the inbound
# webhook (modules/whatsappCloud.py) may change consent from a phone number.


@router.post(
    "/clientContactPreferences",
    summary="Client marketing consent (upsert / delete)",
    description="""
Marketing consent per client and channel. Receipts and operational notices
are never affected. No row = unknown: whatsapp/sms not opted in, push opted in.

action 1 — upsert (one row per companyId + clientId + channel):
  { "clientContactPreferences": [{ "action": 1, "companyId": int, "clientId": int,
    "channel": "whatsapp|sms|push", "marketingOptIn": 0|1,
    "source": "pos_checkout|client_app|admin", "updatedByUserId"?: int }] }

action 3 — delete:
  { "clientContactPreferences": [{ "action": 3, "companyId": int, "clientId": int, "channel": str }] }

Returns: { "result": [{ "value", "msg", "error" }] } (400 when error = "1")
""",
)
def clientContactPreferences(json: dict):
    return clientContactPreferences_sp(json)


@router.post(
    "/all_clientContactPreferences",
    summary="List client marketing consent",
    description="""
Body: { "clientContactPreferences": [{ "companyId": int, "clientId"?: int }] }
Returns: { "clientContactPreferences": ClientContactPreference[] }
""",
)
def all_clientContactPreferences(json: dict):
    return all_clientContactPreferences_sp(json)


@router.post(
    "/one_clientContactPreferences",
    summary="One client marketing consent row",
    description="""
Body: { "clientContactPreferences": [{ "companyId": int, "clientContactPreferenceId": int }] }
Returns: { "clientContactPreferences": [ClientContactPreference] } (empty when not in that company)
""",
)
def one_clientContactPreferences(json: dict):
    return one_clientContactPreferences_sp(json)
