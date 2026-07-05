import json
from fastapi.responses import JSONResponse
from databases import connection
from modules.azure_notifications import send_azure_push


def _sp(payload: dict):
    conn = cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_digitalContracts] @pjsonfile = %s",
            (json.dumps({"contract": [payload]}),)
        )
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


async def digitalContracts_sp(payload: dict):
    action = payload.get("action", "")
    print(f"[digitalContracts] action={action} loanId={payload.get('loanId')} clientId={payload.get('clientId')}")

    result = _sp(payload)

    if isinstance(result, dict) and "error" in result:
        return JSONResponse(content=result, status_code=400)

    # Send push notification when a contract is ready to sign or has been signed
    notify_actions = {"create_contract", "sign_contract", "void_contract"}
    if action in notify_actions and isinstance(result, dict):
        target_user_id = result.get("targetUserId")
        if target_user_id:
            if action == "create_contract":
                title = "📄 Contrato listo para firmar"
                body = f"Tu contrato de préstamo está listo. Firma digitalmente para continuar."
            elif action == "sign_contract":
                title = "✅ Contrato firmado"
                body = "El contrato ha sido firmado por ambas partes. El préstamo está activo."
            elif action == "void_contract":
                title = "❌ Contrato cancelado"
                body = "El contrato de préstamo ha sido cancelado."
            else:
                title = "📄 Actualización de contrato"
                body = "Hay una actualización en tu contrato de préstamo."

            try:
                await send_azure_push(title, body, target_user_id)
                print(f"[digitalContracts] push sent → userId={target_user_id} title={title!r}")
            except Exception as e:
                print(f"[digitalContracts] push failed: {e}")

    return JSONResponse(content=result, status_code=200)
