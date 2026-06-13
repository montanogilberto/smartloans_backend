from fastapi.responses import JSONResponse
from databases import connection
import json

conn = connection()


def suppliers_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_suppliers] @pjsonfile = %s", (json.dumps(json_file),))
        json_result = cursor.fetchall()
        # SP returns ONE row, ONE column ([jsonResult]) → [0][0], NEVER [0][1]
        return JSONResponse(content=json_result[0][0], status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def all_suppliers_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_suppliers_all] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def one_suppliers_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_suppliers_one] @pjsonfile = %s", (json.dumps(json_file),))
        row = cursor.fetchone()
        json_result = row[0] if row else "{}"
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
