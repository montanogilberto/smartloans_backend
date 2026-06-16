from fastapi.responses import JSONResponse
from databases import connection
import json
import httpx
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
        json_result = row[0] if row else '{"message": "ok"}'
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


_FACE_ENDPOINT  = os.getenv("AZURE_FACE_API_ENDPOINT", "").rstrip("/")
_FACE_KEY       = os.getenv("AZURE_FACE_API_KEY", "")
_FACE_HEADERS   = {
    "Ocp-Apim-Subscription-Key": _FACE_KEY,
    "Content-Type": "application/json",
}
_CONFIDENCE_THRESHOLD = 0.6
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


async def verify_clientFaceRecognition_connector(payload: dict) -> JSONResponse:
    """
    Full orchestration:
      1. Upload idFrontImage (base64)  → Azure Blob 'clients' → permanent URL
      2. Upload clientSelfie  (base64) → Azure Blob 'clients' → permanent URL
      3. Detect face in ID image URL   → faceId1  (Azure Face API)
      4. Detect face in selfie URL     → faceId2  (Azure Face API)
      5. Verify faceId1 vs faceId2     → confidenceScore + isVerified
    Returns: { isVerified, confidenceScore, idFrontImageBlobUrl, clientSelfieBlobUrl }
    """
    try:
        company_id     = payload.get("companyId", "0")
        document_type  = payload.get("documentType", "doc").replace(" ", "_")
        ts             = datetime.utcnow().strftime("%Y%m%d%H%M%S")
        uid            = str(uuid.uuid4())[:8]

        # --- Step 1 & 2: upload images to blob storage (same pattern as ticket_receipts.py) ---
        id_b64     = payload.get("idFrontImageBase64", "")
        selfie_b64 = payload.get("clientSelfieBase64", "")

        now = datetime.utcnow()
        yr = str(now.year)
        mo = str(now.month).zfill(2)
        id_blob_path     = "clients/" + yr + "/" + mo + "/" + document_type + "_id_" + ts + "_" + uid + ".jpg"
        selfie_blob_path = "clients/" + yr + "/" + mo + "/selfie_" + ts + "_" + uid + ".jpg"

        id_image_url = _upload_base64_to_blob(
            id_b64, id_blob_path, "image/jpeg",
            {"companyId": str(company_id), "documentType": document_type},
        )
        selfie_url = _upload_base64_to_blob(
            selfie_b64, selfie_blob_path, "image/jpeg",
            {"companyId": str(company_id), "documentType": "selfie"},
        )

        # --- Steps 3–5: Azure Face API ---
        async with httpx.AsyncClient(timeout=30.0) as client:

            # Step 3 — detect face in ID document
            r1 = await client.post(
                _FACE_ENDPOINT + "/face/v1.0/detect",
                headers=_FACE_HEADERS,
                json={"url": id_image_url},
                params={"detectionModel": "detection_03", "recognitionModel": "recognition_04"},
            )
            r1.raise_for_status()
            faces1 = r1.json()
            if not faces1:
                return JSONResponse(
                    content={"isVerified": False, "confidenceScore": 0.0,
                             "error": "No face detected in ID document",
                             "idFrontImageBlobUrl": id_image_url,
                             "clientSelfieBlobUrl": selfie_url},
                    status_code=200,
                )
            face_id_1 = faces1[0]["faceId"]

            # Step 4 — detect face in selfie
            r2 = await client.post(
                _FACE_ENDPOINT + "/face/v1.0/detect",
                headers=_FACE_HEADERS,
                json={"url": selfie_url},
                params={"detectionModel": "detection_03", "recognitionModel": "recognition_04"},
            )
            r2.raise_for_status()
            faces2 = r2.json()
            if not faces2:
                return JSONResponse(
                    content={"isVerified": False, "confidenceScore": 0.0,
                             "error": "No face detected in selfie",
                             "idFrontImageBlobUrl": id_image_url,
                             "clientSelfieBlobUrl": selfie_url},
                    status_code=200,
                )
            face_id_2 = faces2[0]["faceId"]

            # Step 5 — verify match
            r3 = await client.post(
                _FACE_ENDPOINT + "/face/v1.0/verify",
                headers=_FACE_HEADERS,
                json={"faceId1": face_id_1, "faceId2": face_id_2},
            )
            r3.raise_for_status()
            result = r3.json()

        confidence  = result.get("confidence", 0.0)
        is_verified = result.get("isIdentical", False) and confidence >= _CONFIDENCE_THRESHOLD

        return JSONResponse(
            content={
                "isVerified":          is_verified,
                "confidenceScore":     confidence,
                "idFrontImageBlobUrl": id_image_url,
                "clientSelfieBlobUrl": selfie_url,
            },
            status_code=200,
        )
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
