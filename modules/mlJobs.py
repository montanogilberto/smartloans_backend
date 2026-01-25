from fastapi.responses import JSONResponse
from databases import connection
import json

def mlJobs_sp(json_file: dict):
    conn = connection()
    try:
        cursor = conn.cursor()

        cursor.execute(
            "EXEC [dbo].[sp_ml_jobs] @pjsonfile = %s",
            (json.dumps(json_file),)
        )

        rows = cursor.fetchall()
        cols = [desc[0] for desc in cursor.description] if cursor.description else []

        data = [dict(zip(cols, row)) for row in rows] if cols else rows

        return JSONResponse(content=data, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

    finally:
        try:
            conn.close()
        except Exception:
            pass
