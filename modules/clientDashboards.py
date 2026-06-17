from fastapi.responses import JSONResponse
from databases import connection
import json


def clientDashboards_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_ClientDashboards] @pjsonfile = %s", (json.dumps(json_file),))
        # Upsert SP returns ONE row, ONE column -- use fetchone()[0]
        row = cursor.fetchone()
        json_result = row[0] if row else '{"message": "ok"}'
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_clientDashboards_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_ClientDashboards_all] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        # SQL Server may split large FOR JSON output across multiple rows -- always join.
        # Guard against None cells and empty tables (empty table is NOT an error).
        json_result = "".join(row[0] for row in rows if row and row[0])
        if not json_result:
            return JSONResponse(content={"clientDashboards": []}, status_code=200)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def one_clientDashboards_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_ClientDashboards_one] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows if row and row[0])
        if not json_result:
            return JSONResponse(content={"clientDashboards": []}, status_code=200)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()