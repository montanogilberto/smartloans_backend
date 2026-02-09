import json
from fastapi.responses import JSONResponse
from databases import connection


def _normalize_sp_rows(rows):
    """
    Your SP returns rows like:
      value | msg | error | output_json

    Depending on driver settings, fetchall() can return:
      [(value, msg, error, output_json), ...]
    where output_json may already be a dict, or a JSON string, or None.

    This normalizes it into:
      {"result":[{"value": "...", "msg":"...", "error":"0", "output_json": {...}}]}
    """
    result = []

    for r in rows or []:
        # tuple-based row
        value = r[0] if len(r) > 0 else ""
        msg = r[1] if len(r) > 1 else ""
        error = r[2] if len(r) > 2 else "0"
        output_json = r[3] if len(r) > 3 else None

        # If output_json comes as string, try parse it
        if isinstance(output_json, str):
            s = output_json.strip()
            if s:
                try:
                    output_json = json.loads(s)
                except Exception:
                    # keep as raw string if not valid JSON
                    pass

        result.append({
            "value": "" if value is None else str(value),
            "msg": "" if msg is None else str(msg),
            "error": "0" if error is None else str(error),
            "output_json": output_json
        })

    return {"result": result}


def cashRegister_sp(json_file: dict):
    print("[cashRegister_sp] payload:", json.dumps(json_file, ensure_ascii=False))

    conn = None
    cursor = None

    try:
        # ✅ IMPORTANT: new connection per request
        conn = connection()

        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_cashRegister] @pjsonfile = %s",
            (json.dumps(json_file),)
        )

        # ✅ ALWAYS consume result set
        rows = cursor.fetchall()

        # ✅ Normalize and return JSON object
        payload = _normalize_sp_rows(rows)
        return JSONResponse(content=payload, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

    finally:
        # ✅ ALWAYS close cursor/conn to avoid "session busy"
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass

        try:
            if conn:
                conn.close()
        except Exception:
            pass
