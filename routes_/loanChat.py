from fastapi import APIRouter
from modules.loanChat import loanChat_sp, loanChat_config

router = APIRouter()

@router.get("/loanChat/config", summary="Loan Chat — assistant/agent configuration",
    description="""
Single source of truth for the reserved "Asistente SmartLoans" identity.
The frontend must NEVER hardcode the agent clientId — it reads it from here.

  agentClientId     — dbo.clients row acting as the assistant lender (0 = not configured)
  agentEnabled      — true when LOANCHAT_AGENT_CLIENT_ID is set (assistant chats allowed)
  agentReplyEnabled — true when NEGOTIATION_AGENT_URL is also set (real AI replies;
                      otherwise the borrower gets a fallback message)
""")
async def loanChatConfig():
    return loanChat_config()

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
