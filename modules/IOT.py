from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

app = FastAPI()
conn = connection()

def led_status_sp(json_file: dict):
    try:
        cursor = conn.cursor()

        # Execute stored procedure with JSON input
        cursor.execute("EXEC sp_led_status @pjsonfile = %s", (json.dumps(json_file),))

        # Fetch JSON result (SQL returns one row, one column)
        result_row = cursor.fetchone()

        if result_row and result_row[0]:
            # The stored procedure already returns valid JSON (FOR JSON PATH)
            json_output = json.loads(result_row[0])
            return JSONResponse(content=json_output, status_code=200)
        else:
            return JSONResponse(content={"led_status": []}, status_code=204)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

