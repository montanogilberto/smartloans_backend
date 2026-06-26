from fastapi.responses import JSONResponse
from databases import connection
import json

conn = connection()

def clientDashboards_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_clientDashboards] @pjsonfile = %s", (json.dumps(json_file),))
        json_result = cursor.fetchall()
        return JSONResponse(content=json_result[0][0], status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def all_clientDashboards_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_clientDashboards_all] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
