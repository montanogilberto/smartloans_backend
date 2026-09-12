import json
import os
import httpx
from fastapi.responses import JSONResponse
from databases import connection

# LoanAgents_SmartLoans — independent ADK service, same one loanChat.py calls
# for /negotiate. Different route per topic; only 'clients' exists so far.
POS_SUPPORT_AGENT_URL = os.environ.get("NEGOTIATION_AGENT_URL", "").rstrip("/")

# topic -> agent route. Add an entry here (and its agent in
# LoanAgents_SmartLoans) for income/expenses/accounting later — no schema or
# route changes needed on this side.
_TOPIC_ROUTES = {
    "clients": "/support/pos-clients",
}


def _sp(payload: dict):
    conn = cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_posSupportChat] @pjsonfile = %s", (json.dumps({"chat": [payload]}),))
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


async def _generate_agent_reply(conversation_id: int, company_id: int, topic: str,
                                 user_message: str, client_id: int | None) -> str:
    """Calls the LoanAgents_SmartLoans agent service over HTTP for the given
    topic. Raises on failure or on an unrecognized/unwired topic."""
    route = _TOPIC_ROUTES.get(topic)
    if not route:
        raise ValueError(f"No support agent wired for topic={topic!r}")
    if not POS_SUPPORT_AGENT_URL:
        raise ValueError("NEGOTIATION_AGENT_URL env var is not set.")

    async with httpx.AsyncClient(timeout=20.0) as client:
        resp = await client.post(
            f"{POS_SUPPORT_AGENT_URL}{route}",
            json={
                "conversationId": conversation_id,
                "companyId": company_id,
                "message": user_message,
                "clientId": client_id,
            },
        )
        resp.raise_for_status()
        return resp.json()["reply"]


async def posSupportChat_sp(payload: dict):
    action = payload.get("action", "")
    print(f"[posSupportChat] action={action} conv={payload.get('conversationId')} topic={payload.get('topic')}")

    result = _sp(payload)

    if isinstance(result, dict) and "error" in result:
        return JSONResponse(content=result, status_code=400)

    # ── Agent auto-reply ───────────────────────────────────────
    # Every user message gets an immediate reply from the topic's agent —
    # unlike loanChat there's no second human on the other end to wait for.
    if action == "send_message" and payload.get("senderRole") == "user" and isinstance(result, dict):
        conv_id = result.get("conversationId") or payload.get("conversationId")
        company_id = payload.get("companyId")
        topic = payload.get("topic")
        user_message = payload.get("body") or ""
        client_id = payload.get("clientId")

        try:
            reply_text = await _generate_agent_reply(
                conv_id, company_id, topic, user_message, client_id)
        except Exception as e:
            print(f"[posSupportChat] agent reply generation failed: {e}")
            reply_text = "Lo siento, no puedo responder en este momento. Intenta de nuevo más tarde."

        _sp({
            "action": "send_message",
            "conversationId": conv_id,
            "senderRole": "agent",
            "body": reply_text,
        })

    return JSONResponse(content=result, status_code=200)
