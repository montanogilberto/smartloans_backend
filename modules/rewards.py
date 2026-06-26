import json
from fastapi.responses import JSONResponse
from databases import connection


def _sp(payload: dict):
    conn = cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_rewards] @pjsonfile = %s", (json.dumps({"rewards": [payload]}),))
        row = cursor.fetchone()
        raw = row[0] if row and row[0] else "{}"
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


def rewards_sp(payload: dict):
    print("[rewards_sp] action:", payload.get("action"), "company:", payload.get("companyId"))
    result = _sp(payload)
    if "error" in result:
        return JSONResponse(content=result, status_code=400)
    return JSONResponse(content=result, status_code=200)
