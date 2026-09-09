import asyncio
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

from modules.journalEntries import post_income_journal_entry
from modules.notificationDispatch import dispatch_notification_connector

app = FastAPI()


def _get_client_phone(conn, client_id) -> str | None:
    try:
        cur = conn.cursor()
        cur.execute("SELECT cellphone FROM dbo.clients WHERE clientId = %s", (client_id,))
        row = cur.fetchone()
        return row[0] if row and row[0] else None
    except Exception as e:
        print(f"[income] client phone lookup failed: {e}")
        return None


def income_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_income @pjsonfile = %s", (json.dumps(json_file),))

        # Obtener resultado en formato JSON
        result_row = cursor.fetchall()

        if result_row:
            result = []
            for row in result_row:
                result.append({
                    "value": row[0],
                    "msg": row[1],
                    "error": row[2]
                })

            # Best-effort: mirror a successful INSERT into the ledger (Módulo
            # Contabilidad). Never blocks/fails the income response — see
            # modules/journalEntries.py::post_income_journal_entry.
            first_row = (json_file.get("income") or [{}])[0]
            is_new_income = str(first_row.get("action")) == "1" and result and not result[0].get("error")
            try:
                if is_new_income:
                    company_id = first_row.get("companyId")
                    total = first_row.get("total")
                    if company_id and total:
                        post_income_journal_entry(
                            company_id, int(result[0]["value"]), float(total), first_row.get("paymentDate")
                        )
            except Exception as e:
                print(f"[income] accounting auto-post hook failed: {e}")

            # Best-effort: fire the Push -> WhatsApp -> SMS cascade for the
            # client on a successful income. Never blocks/fails the income
            # response. NOTE: this runs independently of the existing manual
            # "Imprimir" ticket flow (ticketApi.ts -> /api/tickets/.../send-*),
            # which still sends its own WhatsApp/SMS when the cashier taps
            # Imprimir -- until one of the two paths is retired, a client can
            # receive two messages for the same sale.
            try:
                if is_new_income:
                    company_id = first_row.get("companyId")
                    client_id = first_row.get("clientId")
                    total = first_row.get("total")
                    income_id = int(result[0]["value"])
                    if company_id and client_id:
                        phone = _get_client_phone(conn, client_id)
                        preview = (
                            f"Gracias por su compra. Total: ${total:,.2f} MXN"
                            if isinstance(total, (int, float)) else "Gracias por su compra."
                        )
                        asyncio.run(dispatch_notification_connector({
                            "companyId": company_id,
                            "sourceType": "income",
                            "sourceId": income_id,
                            "recipientType": "client",
                            "recipientId": client_id,
                            "eventName": "income_created",
                            "phone": phone,
                            "messagePreview": preview,
                        }))
            except Exception as e:
                print(f"[income] notification dispatch hook failed: {e}")

            return JSONResponse(content={"result": result}, status_code=200)
        else:
            return JSONResponse(content={"result": [], "msg": "No data returned"}, status_code=204)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_income_sp():
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_income_all]")

        # Fetch all the results as a list of tuples
        rows = cursor.fetchall()

        # Concatenate JSON strings from all rows into one string
        json_result = "".join(row[0] for row in rows)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()