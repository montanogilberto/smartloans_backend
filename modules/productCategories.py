from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

app = FastAPI()


# ---------------------------------------------------------
# Helper function to execute SP returning JSON
# ---------------------------------------------------------
def execute_sp_json(sp_sql: str, params=()):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()

        cursor.execute(sp_sql, params)

        rows = cursor.fetchall()

        if not rows:
            return None

        # SQL Server FOR JSON may return chunked rows
        json_text = "".join((row[0] or "") for row in rows).strip()

        if not json_text:
            return None

        return json.loads(json_text)

    finally:
        try:
            if conn:
                conn.close()
        except Exception:
            pass


# ---------------------------------------------------------
# PRODUCT CATEGORIES CRUD
# ---------------------------------------------------------
def products_categories_sp(json_file: dict):
    try:
        payload = json.dumps(json_file)

        result = execute_sp_json(
            "EXEC dbo.sp_products_categories @pjsonfile = %s",
            (payload,)
        )

        return JSONResponse(content=result or {"result": []}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------
# ALL PRODUCTS CATEGORIES BY COMPANIES
# ---------------------------------------------------------
def all_products_categories_sp(json_file: dict):
    try:
        payload = json.dumps(json_file)

        result = execute_sp_json(
            "EXEC dbo.sp_products_categories_all @pjsonfile = %s",
            (payload,)
        )

        return JSONResponse(content=result or {"productCategories": []}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


