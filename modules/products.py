from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json
import uuid
from datetime import datetime
from modules.clientFaceRecognitions import (
    BLOB_FOLDER_PRODUCT_IMAGES, company_blob_path, _upload_base64_to_blob,
)
from observability.integrations import timed_integration

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
# PRODUCTS With Details Categories CRUD
# ---------------------------------------------------------
def products_sp(json_file: dict):
    try:
        payload = json.dumps(json_file)

        result = execute_sp_json(
            "EXEC dbo.sp_products @pjsonfile = %s",
            (payload,)
        )

        return JSONResponse(content=result or {"result": []}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------
# ALL PRODUCTS
# ---------------------------------------------------------
def all_products_sp():
    try:
        result = execute_sp_json("EXEC dbo.sp_products_all")

        return JSONResponse(content=result or {"products": []}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------
# ONE PRODUCT
# ---------------------------------------------------------
def one_products_sp(json_file: dict):
    try:
        payload = json.dumps(json_file)

        result = execute_sp_json(
            "EXEC dbo.sp_products_one @pjsonfile = %s",
            (payload,)
        )

        return JSONResponse(content=result or {"products": []}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------
# FOOD PRODUCTS
# ---------------------------------------------------------
def food_products_sp():
    try:
        result = execute_sp_json("EXEC dbo.sp_products_food")

        return JSONResponse(content=result or {"products": []}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------
# FOOD PRODUCT CATEGORIES
# ---------------------------------------------------------
def food_categories_products_sp():
    try:
        result = execute_sp_json("EXEC dbo.sp_products_categories_food")

        return JSONResponse(content=result or {"products": []}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------
# PRODUCTS BY COMPANY
# ---------------------------------------------------------
def by_company_products_sp(json_file: dict):
    try:
        payload = json.dumps(json_file)

        result = execute_sp_json(
            "EXEC dbo.sp_products_by_company @pjsonfile = %s",
            (payload,)
        )

        return JSONResponse(content=result or {"products": []}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------
# PRODUCT IMAGE UPLOAD
# ---------------------------------------------------------
async def upload_product_image_connector(json_file: dict) -> JSONResponse:
    """Uploads a product photo (usually the front photo the label reader used
    to fill "Nuevo Producto") to Azure Blob Storage -- same helpers/container
    as expense receipts, company-scoped folder. Returns: { blobUrl }.
    The caller persists the URL via sp_products (products[].imageUrl) --
    this endpoint only uploads bytes.
        {"companyId": 1, "imageBase64": "data:image/jpeg;base64,..."}"""
    try:
        company_id = json_file.get("companyId", "0")
        image_b64 = json_file.get("imageBase64", "")

        if not image_b64:
            return JSONResponse(content={"error": "imageBase64 is required"}, status_code=400)

        ts = datetime.utcnow().strftime("%Y%m%d%H%M%S")
        uid = str(uuid.uuid4())[:8]
        blob_path = company_blob_path(company_id, BLOB_FOLDER_PRODUCT_IMAGES, f"product_{ts}_{uid}.jpg")

        with timed_integration(
            "azure_blob", "upload_product_image",
            request={"companyId": str(company_id), "blobPath": blob_path},
        ) as span:
            blob_url = _upload_base64_to_blob(
                image_b64, blob_path, "image/jpeg",
                {"companyId": str(company_id)},
            )
            span.response = {"blobUrl": blob_url}
            span.http_status = 200

        return JSONResponse(content={"blobUrl": blob_url}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
