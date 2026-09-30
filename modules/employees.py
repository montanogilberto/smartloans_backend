from fastapi.responses import JSONResponse
from databases import connection
from observability import log_audit
import json

_AUDIT_ACTIONS = {1: "INSERT", 2: "UPDATE", 3: "DELETE"}


def employees_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_employees] @pjsonfile = %s", (json.dumps(json_file),))
        json_result = cursor.fetchall()
        # SP returns ONE row, ONE column ([jsonResult]) → [0][0]
        result = json.loads(json_result[0][0])

        if result.get("status") == "success":
            row = (json_file.get("employees") or [{}])[0]
            action = _AUDIT_ACTIONS.get(int(row.get("action") or 0))
            if action:
                # Ids only — employee rows carry PII (email/phone/address)
                log_audit("employees", int(result.get("value") or 0) or None,
                          "statusId", None, row.get("statusId"), action=action)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_employees_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_employees_all] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        # FOR JSON splits long output across rows; empty result → no rows
        json_result = "".join((row[0] or "") for row in rows).strip()
        if not json_result:
            return JSONResponse(content={"employees": []}, status_code=200)

        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def one_employee_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_employees_one] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join((row[0] or "") for row in rows).strip()
        if not json_result:
            return JSONResponse(content={"employees": []}, status_code=200)

        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
