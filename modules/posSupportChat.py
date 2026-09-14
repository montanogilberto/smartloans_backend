import json
import os
import time
import re
import httpx
from fastapi.responses import JSONResponse
from databases import connection
from modules.clients import clients_sp

# LoanAgents_SmartLoans — independent ADK service, same one loanChat.py calls
# for /negotiate. Different route per topic.
POS_SUPPORT_AGENT_URL = os.environ.get("NEGOTIATION_AGENT_URL", "").rstrip("/")

# topic -> agent route. Each maps to its own pos_{topic}_support_agent in
# LoanAgents_SmartLoans (agents/pos_income_support, pos_expenses_support,
# pos_accounting_support) — no schema or route changes needed on this side.
_TOPIC_ROUTES = {
    "clients": "/support/pos-clients",
    "income": "/support/pos-income",
    "expenses": "/support/pos-expenses",
    "accounting": "/support/pos-accounting",
}

# ── Pending write actions ──────────────────────────────────────────────────
# An agent (see LoanAgents_SmartLoans/tools/pending_actions.py) PROPOSES an
# action; this module is the ONLY place that ever actually executes one, and
# only after the user explicitly confirms. In-process only (no DB table, no
# schema change) — same durability tradeoff this codebase already accepts
# for ADK's own InMemorySessionService. A restart loses any pending
# confirmation, which just means the user has to re-ask — never a silent
# wrong execution.
#
# conversationId -> {"capability": str, "fields": dict, "companyId": int,
#                     "userId": int, "expiresAt": float}
_PENDING_ACTIONS: dict[int, dict] = {}
_PENDING_ACTION_TTL_SECONDS = 600  # 10 minutes

_CONFIRM_WORDS = {"si", "sí", "confirmo", "confirmar", "yes", "ok", "dale", "correcto"}
_CANCEL_WORDS = {"no", "cancelar", "cancel", "cancelo"}


def _classify_confirmation(body: str) -> str | None:
    """Deterministic — never an LLM call for this. A pending write action
    is exactly the kind of thing that must not depend on model reliability
    to detect 'yes'/'no'. Returns 'confirm', 'cancel', or None (treat as an
    unrelated message)."""
    normalized = re.sub(r"[^\w\s]", "", (body or "").strip().lower())
    words = set(normalized.split())
    if words & _CONFIRM_WORDS:
        return "confirm"
    if words & _CANCEL_WORDS:
        return "cancel"
    return None


def _execute_pending_action(pending: dict) -> dict:
    """The ONLY place a proposed action is actually executed. Dispatches to
    the SAME function every other client-creation path in this backend
    uses (modules.clients.clients_sp) — never a parallel write path."""
    capability = pending["capability"]
    fields = pending["fields"]
    company_id = pending["companyId"]

    if capability == "CREATE_CLIENT":
        response = clients_sp({"clients": [{"action": 1, "companyId": company_id, **fields}]})
        try:
            body = json.loads(response.body)
        except Exception:
            return {"error": "unexpected response from clients_sp"}
        if isinstance(body, dict) and body.get("error"):
            return {"error": body["error"]}
        return {"ok": True, "result": body}

    return {"error": f"no executor wired for capability={capability!r}"}


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
                                 user_message: str, client_id: int | None) -> tuple[str, dict | None]:
    """Calls the LoanAgents_SmartLoans agent service over HTTP for the given
    topic. Raises on failure or on an unrecognized/unwired topic. Returns
    (reply_text, pending_action_or_None) — pending_action is whatever the
    agent proposed this turn, if anything."""
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
        data = resp.json()
        return data["reply"], data.get("pendingAction")


async def posSupportChat_sp(payload: dict):
    action = payload.get("action", "")
    print(f"[posSupportChat] action={action} conv={payload.get('conversationId')} topic={payload.get('topic')}")

    result = _sp(payload)

    if isinstance(result, dict) and "error" in result:
        return JSONResponse(content=result, status_code=400)

    # ── Agent auto-reply ───────────────────────────────────────
    # Every user message gets an immediate reply — either from the topic's
    # agent, or, if a write action is pending confirmation for this
    # conversation, from the deterministic confirm/cancel check below
    # (never the agent — it has no memory of the proposal, see
    # tools/pending_actions.py's docstring).
    if action == "send_message" and payload.get("senderRole") == "user" and isinstance(result, dict):
        conv_id = result.get("conversationId") or payload.get("conversationId")
        company_id = payload.get("companyId")
        user_id = payload.get("userId")
        topic = payload.get("topic")
        user_message = payload.get("body") or ""
        client_id = payload.get("clientId")

        pending = _PENDING_ACTIONS.get(conv_id)
        expired = pending and pending["expiresAt"] < time.time()
        # Defense in depth (not a fix for the deeper client-asserted-identity
        # problem noted elsewhere): only confirm/cancel a pending action for
        # the SAME companyId/userId that proposed it, so a request merely
        # guessing a conversationId can't drive someone else's confirmation.
        owned = pending and pending.get("companyId") == company_id and pending.get("userId") == user_id

        if pending and expired:
            _PENDING_ACTIONS.pop(conv_id, None)
            pending = None

        if pending and owned:
            intent = _classify_confirmation(user_message)
            if intent == "confirm":
                exec_result = _execute_pending_action(pending)
                _PENDING_ACTIONS.pop(conv_id, None)
                reply_text = (
                    "Listo, cliente creado correctamente." if exec_result.get("ok")
                    else f"No se pudo crear el cliente: {exec_result.get('error')}"
                )
                _sp({"action": "send_message", "conversationId": conv_id,
                     "senderRole": "agent", "body": reply_text})
                return JSONResponse(content=result, status_code=200)
            if intent == "cancel":
                _PENDING_ACTIONS.pop(conv_id, None)
                _sp({"action": "send_message", "conversationId": conv_id,
                     "senderRole": "agent", "body": "Cancelado, no se creó el cliente."})
                return JSONResponse(content=result, status_code=200)
            # Ambiguous reply to a pending proposal — drop it rather than
            # risk a later unrelated "sí" confirming something stale.
            _PENDING_ACTIONS.pop(conv_id, None)

        try:
            reply_text, pending_action = await _generate_agent_reply(
                conv_id, company_id, topic, user_message, client_id)
        except Exception as e:
            print(f"[posSupportChat] agent reply generation failed: {e}")
            reply_text, pending_action = "Lo siento, no puedo responder en este momento. Intenta de nuevo más tarde.", None

        if pending_action:
            _PENDING_ACTIONS[conv_id] = {
                "capability": pending_action["capability"],
                "fields": pending_action["fields"],
                "companyId": company_id,
                "userId": user_id,
                "expiresAt": time.time() + _PENDING_ACTION_TTL_SECONDS,
            }

        _sp({
            "action": "send_message",
            "conversationId": conv_id,
            "senderRole": "agent",
            "body": reply_text,
        })

    return JSONResponse(content=result, status_code=200)
