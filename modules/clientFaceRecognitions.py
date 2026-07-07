from fastapi.responses import JSONResponse
from databases import connection
import json
import os
from azure.storage.blob import BlobServiceClient, ContentSettings
import base64
import uuid
from datetime import datetime


def clientFaceRecognitions_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_clientFaceRecognitions] @pjsonfile = %s", (json.dumps(json_file),))
        row = cursor.fetchone()
        # row can exist but hold a NULL/empty column (e.g. the SP's FOR JSON
        # SELECT matched no rows) — guard against that the same way `row`
        # itself is guarded, otherwise json.loads('') throws a confusing
        # "Expecting value: line 1 column 1 (char 0)" that hides the real
        # cause (SP found nothing to return).
        json_result = row[0] if row and row[0] else '{"message": "ok"}'
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_clientFaceRecognitions_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_clientFaceRecognitions_all] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows if row and row[0])
        if not json_result:
            return JSONResponse(content={"clientFaceRecognitions": []}, status_code=200)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def one_clientFaceRecognitions_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_clientFaceRecognitions_one] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows if row and row[0])
        if not json_result:
            return JSONResponse(content={"clientFaceRecognitions": []}, status_code=200)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


_CLIENTS_CONTAINER    = os.getenv("CLIENTS_CONTAINER_NAME", "clients")
_ACCOUNT_URL_FALLBACK = os.getenv("AZURE_STORAGE_ACCOUNT_URL_FALLBACK", "")


def _blob_service_client() -> BlobServiceClient:
    conn_str = os.getenv("AZURE_STORAGE_CONNECTION_STRING", "")
    if not conn_str:
        raise RuntimeError("Missing AZURE_STORAGE_CONNECTION_STRING env var")
    return BlobServiceClient.from_connection_string(conn_str)


def _upload_to_blob(raw_bytes: bytes, blob_path: str, content_type: str, metadata: dict) -> str:
    """
    Same pattern as ticket_receipts.py — upload bytes, return public URL.
    Uses service_client.url (falls back to AZURE_STORAGE_ACCOUNT_URL_FALLBACK).
    """
    service_client   = _blob_service_client()
    container_client = service_client.get_container_client(_CLIENTS_CONTAINER)
    blob_client      = container_client.get_blob_client(blob_path)
    blob_client.upload_blob(
        raw_bytes,
        overwrite=True,
        content_settings=ContentSettings(content_type=content_type),
        metadata=metadata,
    )
    account_url = getattr(service_client, "url", None) or _ACCOUNT_URL_FALLBACK
    return account_url.rstrip("/") + "/" + _CLIENTS_CONTAINER + "/" + blob_path


def _upload_base64_to_blob(b64_data: str, blob_path: str, content_type: str, metadata: dict) -> str:
    """Strip optional data-URI prefix then upload."""
    if "," in b64_data:
        b64_data = b64_data.split(",", 1)[1]
    return _upload_to_blob(base64.b64decode(b64_data), blob_path, content_type, metadata)


async def upload_id_image_connector(payload: dict) -> JSONResponse:
    """
    Uploads a single ID/selfie image to Azure Blob Storage on its own, decoupled
    from the full verify+liveness flow, so a capture is saved as soon as it's
    taken instead of only at the end of the wizard.
    Returns: { blobUrl }
    """
    try:
        company_id = payload.get("companyId", "0")
        client_id  = payload.get("clientId", "0")
        side       = payload.get("side", "")
        image_b64  = payload.get("imageBase64", "")

        if side not in ("front", "back", "selfie"):
            return JSONResponse(content={"error": "side must be 'front', 'back', or 'selfie'"}, status_code=400)
        if not image_b64:
            return JSONResponse(content={"error": "imageBase64 is required"}, status_code=400)

        now = datetime.utcnow()
        ts  = now.strftime("%Y%m%d%H%M%S")
        uid = str(uuid.uuid4())[:8]
        blob_path = "clients/" + str(now.year) + "/" + str(now.month).zfill(2) + \
            "/" + side + "_" + str(client_id) + "_" + ts + "_" + uid + ".jpg"

        blob_url = _upload_base64_to_blob(
            image_b64, blob_path, "image/jpeg",
            {"companyId": str(company_id), "clientId": str(client_id), "side": side},
        )

        return JSONResponse(content={"blobUrl": blob_url}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


async def contract_clientFaceRecognition_connector(payload: dict) -> JSONResponse:
    """
    Optionally uploads a base64 contract PDF to blob storage (clients container),
    then persists the final verification + contract record via the standard CRUD SP.
    """
    try:
        contract_url = payload.get("contractPdfBlobUrl", "")

        # Upload contract PDF if caller sent base64 instead of a URL
        contract_b64 = payload.get("contractPdfBase64", "")
        if contract_b64 and not contract_url:
            company_id = payload.get("companyId", "0")
            now        = datetime.utcnow()
            ts         = now.strftime("%Y%m%d%H%M%S")
            uid        = str(uuid.uuid4())[:8]
            blob_path  = "clients/" + str(now.year) + "/" + str(now.month).zfill(2) + "/contract_" + ts + "_" + uid + ".pdf"
            contract_url = _upload_base64_to_blob(
                contract_b64, blob_path, "application/pdf",
                {"companyId": str(company_id), "type": "contract"},
            )

        json_file = {
            "clientFaceRecognitions": [{
                "action":              1,
                "companyId":           payload.get("companyId"),
                "documentType":        payload.get("documentType"),
                "idFrontImageBlobUrl": payload.get("idFrontImageBlobUrl"),
                "clientSelfieBlobUrl": payload.get("clientSelfieBlobUrl"),
                "confidenceScore":     payload.get("confidenceScore", 0.0),
                "isVerified":          payload.get("isVerified", False),
                "contractAccepted":    payload.get("contractAccepted", False),
                "acceptedAt":          payload.get("acceptedAt"),
            }]
        }
        return clientFaceRecognitions_sp(json_file)   # reuse CRUD SP for persistence
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
