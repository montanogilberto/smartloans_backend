from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

app = FastAPI()

def login_sp(json_file: dict):
    conn = None
    cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_login @pjsonfile = %s", (json.dumps(json_file),))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
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
