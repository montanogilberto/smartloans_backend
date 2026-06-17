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


_CONFIDENCE_THRESHOLD = 0.6
_CLIENTS_CONTAINER    = os.getenv("CLIENTS_CONTAINER_NAME", "clients")
_ACCOUNT_URL_FALLBACK = os.getenv("AZURE_STORAGE_ACCOUNT_URL_FALLBACK", "")
_LIVENESS_API_VERSION = os.getenv("AZURE_FACE_LIVENESS_API_VERSION", "v1.1-preview.1")
_LIVENESS_FALLBACK_API_VERSIONS = [
    v.strip()
    for v in os.getenv(
        "AZURE_FACE_LIVENESS_FALLBACK_API_VERSIONS",
        "v1.1-preview.1,v1.0-preview.1,v1.0",
    ).split(",")
    if v.strip()
]
_LIVENESS_CREATE_PATH_TEMPLATE = os.getenv(
    "AZURE_FACE_LIVENESS_CREATE_PATH_TEMPLATE",
    "/face/{version}/liveness/session",
)
_LIVENESS_VERIFY_PATH_TEMPLATE = os.getenv(
    "AZURE_FACE_LIVENESS_VERIFY_PATH_TEMPLATE",
    "/face/{version}/liveness/session/verify/{sessionId}",
)


def _get_face_config():
    endpoint = os.getenv("AZURE_FACE_API_ENDPOINT", "").rstrip("/")
    key = os.getenv("AZURE_FACE_API_KEY", "")
    missing = []
    if not endpoint:
        missing.append("AZURE_FACE_API_ENDPOINT")
    if not key:
        missing.append("AZURE_FACE_API_KEY")
    headers = {
        "Ocp-Apim-Subscription-Key": key,
        "Content-Type": "application/json",
    }
    return endpoint, key, headers, missing


def _build_face_url(base_endpoint: str, template: str, **kwargs) -> str:
    path = template.format(**kwargs).lstrip("/")
    return base_endpoint.rstrip("/") + "/" + path


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


async def create_azure_liveness_session() -> JSONResponse:
    """
    Creates Azure Face Liveness session.
    Frontend uses returned session/auth token for streaming liveness flow.
    Retries across configured API versions to handle regional/version differences.
    """
    attempted_requests = []
    try:
        face_endpoint, _, face_headers, missing = _get_face_config()
        if missing:
            return JSONResponse(
                content={
                    "error": "Missing required Azure Face configuration",
                    "missing": missing,
                },
                status_code=500,
            )

        preferred_versions = [_LIVENESS_API_VERSION] + [
            v for v in _LIVENESS_FALLBACK_API_VERSIONS if v != _LIVENESS_API_VERSION
        ]
        body = {
            "livenessOperationMode": "PassiveAndActive",
            "deviceCorrelationId": str(uuid.uuid4()),
        }

        async with httpx.AsyncClient(timeout=30.0) as client:
            last_error = None
            for version in preferred_versions:
                endpoint = _build_face_url(
                    face_endpoint,
                    _LIVENESS_CREATE_PATH_TEMPLATE,
                    version=version,
                )
                try:
                    r = await client.post(endpoint, headers=face_headers, json=body)
                    attempted_requests.append(
                        {"version": version, "url": endpoint, "statusCode": r.status_code}
                    )
                    r.raise_for_status()
                    data = r.json()
                    return JSONResponse(
                        content={
                            "sessionId": data.get("sessionId"),
                            "authToken": data.get("authToken"),
                            "raw": data,
                            "apiVersionUsed": version,
                        },
                        status_code=200,
                    )
                except httpx.HTTPStatusError as http_err:
                    last_error = http_err
                    continue
                except Exception as e:
                    return JSONResponse(
                        content={
                            "error": str(e),
                            "requestMethod": "POST",
                            "requestUrl": endpoint,
                            "attemptedRequests": attempted_requests,
                        },
                        status_code=500,
                    )

        return JSONResponse(
            content={
                "error": str(last_error) if last_error else "Unable to create liveness session",
                "requestMethod": "POST",
                "requestUrl": attempted_requests[-1]["url"] if attempted_requests else None,
                "attemptedRequests": attempted_requests,
            },
            status_code=500,
        )
    except Exception as e:
        return JSONResponse(
            content={
                "error": str(e),
                "requestMethod": "POST",
                "requestUrl": attempted_requests[-1]["url"] if attempted_requests else None,
                "attemptedRequests": attempted_requests,
            },
            status_code=500,
        )


async def verify_clientFaceRecognition_connector(payload: dict) -> JSONResponse:
    """
    Liveness orchestration:
      1. Upload idFrontImage (base64)  → Azure Blob 'clients' → permanent URL
      2. Read Azure liveness session result by azureSessionId
      3. Extract liveness + verify outcomes
      4. Store extracted selfie frame (if present) in blob as clientSelfieBlobUrl
    Returns: { isVerified, confidenceScore, idFrontImageBlobUrl, clientSelfieBlobUrl }
    """
    try:
        company_id     = payload.get("companyId", "0")
        document_type  = payload.get("documentType", "doc").replace(" ", "_")
        azure_session_id = payload.get("azureSessionId", "")
        id_b64 = payload.get("idFrontImageBase64", "")

        if not azure_session_id:
            return JSONResponse(content={"error": "azureSessionId is required"}, status_code=400)
        if not id_b64:
            return JSONResponse(content={"error": "idFrontImageBase64 is required"}, status_code=400)

        ts  = datetime.utcnow().strftime("%Y%m%d%H%M%S")
        uid = str(uuid.uuid4())[:8]
        now = datetime.utcnow()
        yr = str(now.year)
        mo = str(now.month).zfill(2)

        id_blob_path = "clients/" + yr + "/" + mo + "/" + document_type + "_id_" + ts + "_" + uid + ".jpg"
        selfie_blob_path = "clients/" + yr + "/" + mo + "/selfie_" + ts + "_" + uid + ".jpg"

        id_image_url = _upload_base64_to_blob(
            id_b64, id_blob_path, "image/jpeg",
            {"companyId": str(company_id), "documentType": document_type},
        )

        face_endpoint, _, face_headers, missing = _get_face_config()
        if missing:
            return JSONResponse(
                content={
                    "error": "Missing required Azure Face configuration",
                    "missing": missing,
                },
                status_code=500,
            )

        result_endpoint = _build_face_url(
            face_endpoint,
            _LIVENESS_VERIFY_PATH_TEMPLATE,
            version=_LIVENESS_API_VERSION,
            sessionId=azure_session_id,
        )

        async with httpx.AsyncClient(timeout=30.0) as client:
            r = await client.get(result_endpoint, headers=face_headers)
            r.raise_for_status()
            azure_result = r.json()

        liveness_result = azure_result.get("livenessResult", {}) or {}
        verify_result = azure_result.get("verifyResult", {}) or {}

        liveness_decision = str(liveness_result.get("livenessDecision", "")).lower()
        is_live = liveness_decision == "realface"
        is_identical = bool(verify_result.get("isIdentical", False))
        confidence = float(verify_result.get("confidence", 0.0) or 0.0)

        extracted_face = verify_result.get("extractedFace")
        selfie_url = ""
        if isinstance(extracted_face, str) and extracted_face.strip():
            selfie_url = _upload_base64_to_blob(
                extracted_face, selfie_blob_path, "image/jpeg",
                {"companyId": str(company_id), "documentType": "selfie"},
            )
        else:
            # fallback so response schema remains intact
            selfie_url = id_image_url

        is_verified = is_live and is_identical and confidence >= _CONFIDENCE_THRESHOLD

        return JSONResponse(
            content={
                "isVerified": is_verified,
                "confidenceScore": confidence,
                "idFrontImageBlobUrl": id_image_url,
                "clientSelfieBlobUrl": selfie_url,
            },
            status_code=200,
        )
    except Exception as e:
        return JSONResponse(
            content={
                "error": str(e),
                "requestMethod": "GET",
                "requestUrl": result_endpoint if "result_endpoint" in locals() else None,
            },
            status_code=500,
        )


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
