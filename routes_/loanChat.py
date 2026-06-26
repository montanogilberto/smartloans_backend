from fastapi import APIRouter
from modules.loanChat import loanChat_sp

router = APIRouter()

@router.post("/loanChat", summary="Loan Chat — conversational loan negotiation",
    description="""
actions:
  start_conversation  — open or reuse a chat between borrower and lender
  send_message        — send text, proposal, or counter-offer (push notification auto-fired)
  list_messages       — all messages in a conversation
  mark_read           — mark unread messages as read
  accept_proposal     — borrower/lender accepts; updates conversation status to 'accepted'
  reject_proposal     — rejects current proposal; status → 'rejected'
  list_conversations  — all conversations for a client (borrower or lender)
  get_conversation    — single conversation by conversationId

Body: { "chat": [{ "action": "...", "companyId": int, ...fields }] }
""")
async def loanChat(json: dict):
    payload = json.get("chat", [{}])[0] if isinstance(json.get("chat"), list) else json
    return await loanChat_sp(payload)
