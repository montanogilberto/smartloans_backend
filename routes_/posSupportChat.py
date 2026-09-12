from fastapi import APIRouter
from modules.posSupportChat import posSupportChat_sp

router = APIRouter()

@router.post("/posSupportChat", summary="POS Soporte — topic-scoped support chat",
    description="""
actions:
  start_conversation  — open or reuse this user's open thread for a topic
  send_message        — send a user message; the topic's agent replies automatically
  list_messages       — all messages in a conversation
  list_conversations  — all conversations for a user

topics: "clients" (Clientes registration wizard). income | expenses | accounting
planned later — sending to an unwired topic returns a graceful fallback reply,
not an error.

Body: { "chat": [{ "action": "...", "companyId": int, ...fields }] }
""")
async def posSupportChat(json: dict):
    payload = json.get("chat", [{}])[0] if isinstance(json.get("chat"), list) else json
    return await posSupportChat_sp(payload)
