from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

app = FastAPI()
conn = connection()

def messageTickets_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_messageTickets] @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchall()

        #print(json_result[0][1])

        # Parse the JSON string to a Python dictionary
        #result = json.loads(json_result[0][1])

        return JSONResponse(content=json_result[0][1], status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

