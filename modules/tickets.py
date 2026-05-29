from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

app = FastAPI()
conn = connection()

def one_tickets_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC sp_tickets_one @pjsonfile = %s", (json.dumps(json_file),))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def one_ticket_tracking_sp(json_file: dict):
    try:
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
