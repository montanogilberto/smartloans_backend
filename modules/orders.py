from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

app = FastAPI()
conn = connection()

def orders_sp(json_file: dict):
    print(json_file)
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_orders] @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchall()
        print(json_result)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

def all_orders_sp():

    try:
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_orders_all]")

        # Fetch all the results as a list of tuples
        rows = cursor.fetchall()

        # Concatenate JSON strings from all rows into one string
        json_result = "".join(row[0] for row in rows)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def one_orders_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        print(json.dumps(json_file))
        cursor.execute("EXEC sp_orders_one @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]
        print("Raw JSON from SP:", json_result)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)
        print(result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)