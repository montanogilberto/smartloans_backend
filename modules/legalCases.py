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
            "EXEC [dbo].[sp_legalCases] @pjsonfile = %s",
            (json.dumps({"case": [payload]}),)
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


async def legalCases_sp(payload: dict):
    action = payload.get("action", "")
    print(f"[legalCases] action={action} loanId={payload.get('loanId')} caseId={payload.get('caseId')}")

    result = _sp(payload)

    if isinstance(result, dict) and "error" in result:
        return JSONResponse(content=result, status_code=400)

    # Push notifications for key legal case events
    notify_actions = {
        "open_case", "assign_lawyer", "update_status",
        "close_case", "embargo_executed"
    }
    if action in notify_actions and isinstance(result, dict):
        lender_user_id = result.get("lenderUserId")
        lawyer_user_id = result.get("lawyerUserId")

        push_map = {
            "open_case": (
                "⚖️ Caso legal abierto",
                "Se ha iniciado el proceso de recuperación para tu préstamo."
            ),
            "assign_lawyer": (
                "👨‍⚖️ Abogado asignado",
                f"El Lic. {result.get('lawyerName', '')} tomará tu caso de recuperación."
            ),
            "update_status": (
                "📋 Actualización del caso",
                result.get("statusNote") or "Tu caso legal ha sido actualizado."
            ),
            "close_case": (
                "✅ Caso cerrado",
                "El proceso de recuperación ha concluido."
            ),
            "embargo_executed": (
                "🏛️ Embargo ejecutado",
                "Se ha ejecutado el embargo. El capital será recuperado."
            ),
        }

        title, body = push_map.get(action, ("⚖️ Caso legal", "Actualización en tu caso legal."))

        for uid in filter(None, [lender_user_id, lawyer_user_id]):
            try:
                await send_azure_push(title, body, uid)
                print(f"[legalCases] push sent → userId={uid} title={title!r}")
            except Exception as e:
                print(f"[legalCases] push failed: {e}")

    return JSONResponse(content=result, status_code=200)
