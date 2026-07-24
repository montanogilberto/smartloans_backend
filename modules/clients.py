from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
from azure.storage.blob import BlobServiceClient, ContentSettings
from modules.clientFaceRecognitions import client_blob_path
import json, base64, uuid, os
from datetime import datetime

app = FastAPI()

_CLIENTS_CONTAINER = os.getenv("CLIENTS_CONTAINER_NAME", "clients")


def _blob_service_client() -> BlobServiceClient:
    conn_str = os.getenv("AZURE_STORAGE_CONNECTION_STRING", "")
    if not conn_str:
        raise RuntimeError("Missing AZURE_STORAGE_CONNECTION_STRING env var")
    return BlobServiceClient.from_connection_string(conn_str)


def _upload_bytes_to_blob(raw_bytes: bytes, blob_path: str, content_type: str, metadata: dict) -> str:
    svc = _blob_service_client()
    cc  = svc.get_container_client(_CLIENTS_CONTAINER)
    bc  = cc.get_blob_client(blob_path)
    bc.upload_blob(raw_bytes, overwrite=True,
                   content_settings=ContentSettings(content_type=content_type),
                   metadata=metadata)
    account_url = svc.url or os.getenv("AZURE_STORAGE_ACCOUNT_URL_FALLBACK", "")
    return account_url.rstrip("/") + "/" + _CLIENTS_CONTAINER + "/" + blob_path

def clients_sp(json_file: dict):
    print(json_file)
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_clients] @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchall()

        #print(json_result[0][1])

        # Parse the JSON string to a Python dictionary
        #result = json.loads(json_result[0][1])

        return JSONResponse(content=json_result[0][1], status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_clients_sp():
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_clients_all]")

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
        if conn:
            conn.close()

def one_clients_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_clients_one @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        row = cursor.fetchone()
        if not row or not row[0]:
            return JSONResponse(content={"clients": []}, status_code=200)

        # Parse the JSON string to a Python dictionary
        result = json.loads(row[0])

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


async def upload_client_qr_sp(json_file: dict):
    """Upload QR PNG to Azure Blob Storage and persist the URL in dbo.clients."""
    db_conn = None
    try:
        data       = (json_file.get("clients") or [{}])[0]
        client_id  = data.get("clientId")
        company_id = data.get("companyId")
        qr_base64  = data.get("qrBase64", "")

        if not client_id or not qr_base64:
            return JSONResponse(content={"error": "clientId and qrBase64 are required"}, status_code=400)

        # Strip optional data-URI prefix
        if "," in qr_base64:
            qr_base64 = qr_base64.split(",", 1)[1]

        raw_bytes = base64.b64decode(qr_base64)

        now = datetime.utcnow()
        uid = str(uuid.uuid4())[:8]
        # Grouped under the client alongside their other assets — same layout
        # as the expediente uploads (see client_blob_path in
        # clientFaceRecognitions.py). 'qr' isn't part of the expediente, but
        # splitting one client's files across two schemes defeats the point.
        blob_path = client_blob_path(client_id, "qr", f"qr_{now.strftime('%Y%m%d%H%M%S')}_{uid}.png")

        qr_url = _upload_bytes_to_blob(raw_bytes, blob_path, "image/png", {
            "clientId":  str(client_id),
            "companyId": str(company_id or ""),
            "type":      "qr",
        })

        # Persist URL in dbo.clients via sp_clients_qr
        db_conn = connection()
        cursor  = db_conn.cursor()
        payload = {"clients": [{"clientId": client_id, "companyId": company_id, "qrBlobUrl": qr_url}]}
        cursor.execute("EXEC [dbo].[sp_clients_qr] @pjsonfile = %s", (json.dumps(payload),))

        return JSONResponse(content={"qrBlobUrl": qr_url}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if db_conn:
            db_conn.close()
