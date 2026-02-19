from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

app = FastAPI()
conn = connection()

def sellListings_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_sellListings] @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchall()

        #print(json_result[0][1])

        # Parse the JSON string to a Python dictionary
        #result = json.loads(json_result[0][1])

        return JSONResponse(content=json_result[0][1], status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

def all_sellListings_sp():

    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_sellListings_all]")

        # Fetch all the results as a list of tuples
        rows = cursor.fetchall()

        # Concatenate JSON strings from all rows into one string
        json_result = "".join(row[0] for row in rows)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def query_sellListings_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC sp_sellListings_query @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

