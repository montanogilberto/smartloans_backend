import json
import os
import httpx
from fastapi.responses import JSONResponse
from databases import connection
from modules.azure_notifications import send_azure_push

# Reserved dbo.clients row (clientType='lender') that borrowers chat with
# for automated negotiation help — see modules/loanChat.py's send_message hook.
AGENT_CLIENT_ID = int(os.environ.get("LOANCHAT_AGENT_CLIENT_ID", "0")) or None

# LoanAgents_SmartLoans — independent ADK service, called over HTTP only.
NEGOTIATION_AGENT_URL = os.environ.get("NEGOTIATION_AGENT_URL", "").rstrip("/")


def _sp(payload: dict):
    conn = cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_loanChat] @pjsonfile = %s", (json.dumps({"chat": [payload]}),))
        row = cursor.fetchone()
        raw = row[0] if row and row[0] else "null"
        return json.loads(raw) if isinstance(raw, str) else raw
    except Exception as e:
        return {"error": str(e)}
    finally:
        try:
            if cursor: cursor.close()
        except Exception: pass
        try:
            if conn: conn.close()
        except Exception: pass


async def _generate_agent_reply(conversation_id: int, borrower_id: int, company_id: int,
                                user_message: str, speaker_role: str = "borrower",
                                topic: str | None = None) -> str:
    """Calls the LoanAgents_SmartLoans agent service (an independent ADK
    service — see https://github.com/montanogilberto/LoanAgents_SmartLoans)
    over HTTP. `speaker_role` tells it who is asking (borrower o lender —
    lenders get the support/GUÍA experience); `topic` routes to the right
    sub-agent: 'account' | 'contract' | 'legal' (GUÍA). Raises on failure."""
    if not NEGOTIATION_AGENT_URL:
        raise ValueError("NEGOTIATION_AGENT_URL env var is not set.")

    async with httpx.AsyncClient(timeout=20.0) as client:
        resp = await client.post(
            f"{NEGOTIATION_AGENT_URL}/negotiate",
            json={
                "conversationId": conversation_id,
                "borrowerId": borrower_id,
                "companyId": company_id,
                "message": user_message,
                "speakerRole": speaker_role,
                "topic": topic,
            },
        )
        resp.raise_for_status()
        return resp.json()["reply"]


def loanChat_config():
    """Config the frontend reads at runtime so the agent identity lives in ONE
    place (the LOANCHAT_AGENT_CLIENT_ID env var), never hardcoded client-side."""
    return {
        "agentClientId": AGENT_CLIENT_ID or 0,
        "agentEnabled": bool(AGENT_CLIENT_ID),
        "agentReplyEnabled": bool(AGENT_CLIENT_ID and NEGOTIATION_AGENT_URL),
    }


def _tag_assistant(result):
    """Mark conversations whose lender is the reserved agent so the frontend can
    switch to assistant mode without knowing the agent's clientId."""
    if not AGENT_CLIENT_ID:
        return
    rows = result if isinstance(result, list) else [result]
    for row in rows:
        if isinstance(row, dict) and "lenderId" in row:
            row["isAssistant"] = row.get("lenderId") == AGENT_CLIENT_ID


async def loanChat_sp(payload: dict):
    action = payload.get("action", "")
    print(f"[loanChat] action={action} conv={payload.get('conversationId')} client={payload.get('clientId')}")

    result = _sp(payload)

    if isinstance(result, dict) and "error" in result:
        return JSONResponse(content=result, status_code=400)

    if action in ("start_conversation", "get_conversation", "list_conversations"):
        _tag_assistant(result)

    # ── Send push notification after message events ───────────
    push_actions = {"send_message", "accept_proposal", "reject_proposal", "start_conversation"}
    if action in push_actions and isinstance(result, dict):
        target_user_id = result.get("targetUserId")
        if target_user_id:
            conv_id = result.get("conversationId") or payload.get("conversationId")
            msg_type = result.get("msgType") or action

            # Build push title/body based on event
            if action == "accept_proposal":
                title = "✅ Préstamo aceptado"
                body  = f"Monto: ${result.get('agreedAmount', 0):,.2f} · Tasa: {result.get('agreedRate', 0)}%"
            elif action == "reject_proposal":
                title = "❌ Propuesta rechazada"
                body  = "La contraparte rechazó la propuesta."
            elif msg_type == "proposal" or msg_type == "counter":
                amount = result.get("amount") or payload.get("amount", 0)
                rate   = result.get("rate")   or payload.get("rate", 0)
                title  = "💰 Nueva propuesta de préstamo"
                body   = f"${amount:,.2f} al {rate}%"
            elif action == "start_conversation":
                title = "📨 Nueva solicitud de préstamo"
                body  = payload.get("title") or "Alguien quiere negociar un préstamo contigo."
            else:
                title = "💬 Nuevo mensaje"
                body  = payload.get("body") or "Tienes un nuevo mensaje en tu préstamo."

            try:
                # navigationRoute lets the app open THIS conversation on tap.
                await send_azure_push(title, body, target_user_id,
                                      data={"navigationRoute": f"/loan-chat/{conv_id}"})
                print(f"[loanChat] push sent → userId={target_user_id} title={title!r} route=/loan-chat/{conv_id}")
            except Exception as e:
                print(f"[loanChat] push failed: {e}")

    # ── Agent auto-reply ───────────────────────────────────────
    # Anyone (borrower OR lender) messaging the reserved "Asistente
    # SmartLoans" gets a reply from the LoanAgents_SmartLoans ADK service.
    # Assistant conversations always put the human in the borrower SLOT
    # (positional), so senderRole is informational — lenders use this for
    # support: cuenta, contratos y legal (GUÍA).
    sender_is_agent = int(payload.get("senderId") or 0) == (AGENT_CLIENT_ID or -1)
    if action == "send_message" and AGENT_CLIENT_ID and not sender_is_agent and isinstance(result, dict):
        conv_id = result.get("conversationId") or payload.get("conversationId")
        conversation = _sp({"action": "get_conversation", "conversationId": conv_id})
        if isinstance(conversation, dict) and conversation.get("lenderId") == AGENT_CLIENT_ID:
            borrower_id = conversation.get("borrowerId")
            company_id = conversation.get("companyId")
            borrower_user_id = conversation.get("borrowerUserId")
            user_message = payload.get("body") or ""

            try:
                reply_text = await _generate_agent_reply(
                    conv_id, borrower_id, company_id, user_message,
                    speaker_role=payload.get("senderRole") or "borrower",
                    topic=payload.get("topic"))
            except Exception as e:
                print(f"[loanChat] agent reply generation failed: {e}")
                reply_text = "Lo siento, no puedo responder en este momento. Intenta de nuevo más tarde."

            agent_result = _sp({
                "action": "send_message",
                "conversationId": conv_id,
                "senderId": AGENT_CLIENT_ID,
                "senderRole": "lender",
                "msgType": "text",
                "body": reply_text,
            })

            if borrower_user_id and isinstance(agent_result, dict) and "error" not in agent_result:
                try:
                    await send_azure_push("🤖 Asistente SmartLoans", reply_text, borrower_user_id,
                                          data={"navigationRoute": f"/loan-chat/{conv_id}"})
                except Exception as e:
                    print(f"[loanChat] agent reply push failed: {e}")

    return JSONResponse(content=result, status_code=200)
