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
            "EXEC [dbo].[sp_disbursement] @pjsonfile = %s",
            (json.dumps({"disbursement": [payload]}),)
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


async def disbursement_sp(payload: dict):
    action = payload.get("action", "")
    print(f"[disbursement] action={action} loanId={payload.get('loanId')} clientId={payload.get('clientId')}")

    result = _sp(payload)

    if isinstance(result, dict) and "error" in result:
        return JSONResponse(content=result, status_code=400)

    # Push notifications for disbursement lifecycle
    notify_actions = {"initiate", "confirm_sent", "confirm_received", "failed"}
    if action in notify_actions and isinstance(result, dict):
        borrower_id = result.get("borrowerUserId")
        lender_id = result.get("lenderUserId")

        if action == "initiate":
            lender_title = "🏦 Desembolso iniciado"
            lender_body = f"Transfiere ${result.get('amount', 0):,.2f} al acreditado para activar el préstamo."
            if lender_id:
                try:
                    await send_azure_push(lender_title, lender_body, lender_id)
                    print(f"[disbursement] push sent → lenderId={lender_id}")
                except Exception as e:
                    print(f"[disbursement] push failed: {e}")

        elif action == "confirm_sent":
            if borrower_id:
                try:
                    await send_azure_push(
                        "💸 Transferencia en camino",
                        f"El prestamista ha enviado ${result.get('amount', 0):,.2f}. Revisa tu cuenta en 24 hrs.",
                        borrower_id
                    )
                    print(f"[disbursement] push sent → borrowerId={borrower_id}")
                except Exception as e:
                    print(f"[disbursement] push failed: {e}")

        elif action == "confirm_received":
            for uid, role in [(borrower_id, "borrower"), (lender_id, "lender")]:
                if uid:
                    try:
                        await send_azure_push(
                            "✅ Préstamo activo",
                            f"El desembolso de ${result.get('amount', 0):,.2f} fue confirmado. El préstamo está activo.",
                            uid
                        )
                        print(f"[disbursement] push sent → {role}Id={uid}")
                    except Exception as e:
                        print(f"[disbursement] push failed {role}: {e}")

        elif action == "failed":
            for uid in filter(None, [borrower_id, lender_id]):
                try:
                    await send_azure_push(
                        "⚠️ Error en el desembolso",
                        result.get("errorNote") or "Hubo un problema con la transferencia. Contacta a soporte.",
                        uid
                    )
                    print(f"[disbursement] push sent → userId={uid}")
                except Exception as e:
                    print(f"[disbursement] push failed: {e}")

    return JSONResponse(content=result, status_code=200)
