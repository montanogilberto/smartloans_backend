from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
from modules.posRewards import ticket_rewards
import json

app = FastAPI()


def execute_sp_json(sp_sql: str, params=()):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(sp_sql, params)

        rows = cursor.fetchall()
        if not rows:
            return None

        json_text = "".join((row[0] or "") for row in rows).strip()
        if not json_text:
            return None

        return json.loads(json_text)
    finally:
        if conn:
            conn.close()


def _add_rewards(result) -> None:
    """Each ticket gets "rewards": {pointsEarned, balance, lines} — the POS
    points block of the sale message — so the printed and the digital ticket
    show it too. Best-effort: a ticket without it just prints without it."""
    if isinstance(result, dict) and isinstance(result.get("tickets"), list):
        tickets = result["tickets"]
    elif isinstance(result, dict) and isinstance(result.get("ticket"), dict):
        tickets = [result["ticket"]]
    elif isinstance(result, dict) and result.get("incomeId"):
        tickets = [result]
    elif isinstance(result, list):
        tickets = result
    else:
        tickets = []
    for t in tickets:
        if isinstance(t, dict) and t.get("incomeId") and t.get("companyId"):
            client_id = (t.get("client") or {}).get("clientId") if isinstance(t.get("client"), dict) else None
            t["rewards"] = ticket_rewards(t["companyId"], t["incomeId"], client_id)


def one_tickets_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_tickets_one @pjsonfile = %s", (json.dumps(json_file),))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)
        _add_rewards(result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def one_ticket_tracking_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_ticket_tracking @pjsonfile = %s", (json.dumps(json_file),))

        row = cursor.fetchone()
        if not row or row[0] is None:
            return JSONResponse(
                content={
                    "success": False,
                    "message": "sp_ticket_tracking returned no data",
                    "request": json_file
                },
                status_code=200
            )

        raw_result = row[0]

        if isinstance(raw_result, (dict, list)):
            return JSONResponse(content=raw_result, status_code=200)

        if isinstance(raw_result, str):
            try:
                result = json.loads(raw_result)
                return JSONResponse(content=result, status_code=200)
            except json.JSONDecodeError:
                return JSONResponse(
                    content={"success": True, "rawResult": raw_result},
                    status_code=200
                )

        return JSONResponse(content={"success": True, "rawResult": str(raw_result)}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def ticket_redirect_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_ticket_redirect @pjsonfile = %s", (json.dumps(json_file),))

        json_result = cursor.fetchone()[0]
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
