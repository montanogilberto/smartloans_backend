import json
from fastapi.responses import JSONResponse
from databases import connection
from modules.azure_notifications import send_azure_push


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


async def loanChat_sp(payload: dict):
    action = payload.get("action", "")
    print(f"[loanChat] action={action} conv={payload.get('conversationId')} client={payload.get('clientId')}")

    result = _sp(payload)

    if isinstance(result, dict) and "error" in result:
        return JSONResponse(content=result, status_code=400)

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
                await send_azure_push(title, body, target_user_id)
                print(f"[loanChat] push sent → userId={target_user_id} title={title!r}")
            except Exception as e:
                print(f"[loanChat] push failed: {e}")

    return JSONResponse(content=result, status_code=200)
