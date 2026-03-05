from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

app = FastAPI()
conn = connection()

def products_sp(json_file: dict):
    #print(json_file)
    try:

        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_products] @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchall()

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            conn.close()
        except Exception:
            pass


def all_products_sp():
    try:

        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_products_all]")

        # Fetch all the results as a list of tuples
        rows = cursor.fetchall()

        # Concatenate JSON strings from all rows into one string
        json_result = "".join(row[0] for row in rows)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            conn.close()
        except Exception:
            pass

def one_products_sp(json_file: dict):
    try:

        cursor = conn.cursor()
        cursor.execute("EXEC sp_products_one @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            conn.close()
        except Exception:
            pass

def food_products_sp():
    try:

        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_products_food]")

        # Fetch all the results as a list of tuples
        rows = cursor.fetchall()

        # Concatenate JSON strings from all rows into one string
        json_result = "".join(row[0] for row in rows)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            conn.close()
        except Exception:
            pass

def food_categories_products_sp():
    try:

        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_products_categories_food]")

        # Fetch all the results as a list of tuples
        rows = cursor.fetchall()

        # Concatenate JSON strings from all rows into one string
        json_result = "".join(row[0] for row in rows)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            conn.close()
        except Exception:
            pass

def by_company_products_sp(json_file: dict):
    try:
        cursor = conn.cursor()

        payload = json.dumps(json_file)

        cursor.execute( "EXEC dbo.sp_products_by_company @pjsonfile = %s",(payload,))

        rows = cursor.fetchall()
        if not rows:
            return JSONResponse(content={"products": []}, status_code=200)

        json_result = "".join((r[0] or "") for r in rows)

        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

    finally:
        try:
            if conn:
                conn.close()
        except Exception:
            pass


def by_company_products_category_sp(json_file: dict):
    try:

        cursor = conn.cursor()
        cursor.execute("EXEC sp_products_categories_by_company @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            conn.close()
        except Exception:
            pass



def products_categories_sp(json_file: dict):

    try:

        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_product_categories] @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            conn.close()
        except Exception:
            pass
