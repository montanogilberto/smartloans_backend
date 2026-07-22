from fastapi.responses import JSONResponse
from databases import connection
import json
import os
from azure.storage.blob import BlobServiceClient, ContentSettings
import base64
import uuid
from datetime import datetime


def clientFaceRecognitions_sp(json_file: dict):
    """
    sp_clientFaceRecognitions' Finish: block returns three flat scalar
    columns (value, msg, error) — NOT a single JSON-blob column like most
    other SPs in this codebase. `value` holds the affected row's
    clientFaceRecognitionId (as text) on insert/update, which the frontend
    needs back to keep updating the same row across capture steps.
    """
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_clientFaceRecognitions] @pjsonfile = %s", (json.dumps(json_file),))
        row = cursor.fetchone()
        if not row:
            return JSONResponse(content={"message": "ok"}, status_code=200)

        value, msg, error = row[0], row[1], row[2]
        client_face_recognition_id = int(value) if value not in (None, "") else None
        content = {"msg": msg, "error": bool(error)}
        if client_face_recognition_id is not None:
            content["clientFaceRecognitionId"] = client_face_recognition_id
        return JSONResponse(content=content, status_code=200)
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


async def upload_presence_capture_connector(payload: dict) -> JSONResponse:
    """
    Uploads a short "presence" video (recorded alongside GPS coordinates for
    address/location verification evidence — OCR can't reliably read a
    printed address off an INE, see idOcr.ts/document_intelligence.py) to
    Azure Blob Storage. Same shape as upload_id_image_connector: this only
    uploads the bytes and returns the URL; the frontend persists it (plus
    the GPS fields, which never touch this endpoint) via the normal
    clientFaceRecognitions_sp update call, same two-step pattern already
    used for ID images.
    Returns: { blobUrl }
    """
    try:
        company_id = payload.get("companyId", "0")
        client_id  = payload.get("clientId", "0")
        video_b64  = payload.get("videoBase64", "")

        if not video_b64:
            return JSONResponse(content={"error": "videoBase64 is required"}, status_code=400)

        now = datetime.utcnow()
        ts  = now.strftime("%Y%m%d%H%M%S")
        uid = str(uuid.uuid4())[:8]
        blob_path = "clients/presence/" + str(now.year) + "/" + str(now.month).zfill(2) + \
            "/presence_" + str(client_id) + "_" + ts + "_" + uid + ".mp4"

        blob_url = _upload_base64_to_blob(
            video_b64, blob_path, "video/mp4",
            {"companyId": str(company_id), "clientId": str(client_id)},
        )

        return JSONResponse(content={"blobUrl": blob_url}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


async def contract_clientFaceRecognition_connector(payload: dict) -> JSONResponse:
    """
    Optionally uploads base64 contract/pagaré PDFs to blob storage (clients
    container), then persists the final verification + contract record via
    the standard CRUD SP.

    When clientFaceRecognitionId is provided (the row already created by the
    front/back/selfie capture steps), this UPDATEs that row instead of
    INSERTing a new one — otherwise every contract submission left an
    orphaned duplicate row with no clientId and no back-image/pagaré data.
    """
    try:
        now = datetime.utcnow()
        ts  = now.strftime("%Y%m%d%H%M%S")

        contract_url = payload.get("contractPdfBlobUrl", "")
        contract_b64 = payload.get("contractPdfBase64", "")
        if contract_b64 and not contract_url:
            uid = str(uuid.uuid4())[:8]
            blob_path = "clients/" + str(now.year) + "/" + str(now.month).zfill(2) + "/contract_" + ts + "_" + uid + ".pdf"
            contract_url = _upload_base64_to_blob(
                contract_b64, blob_path, "application/pdf",
                {"companyId": str(payload.get("companyId", "0")), "type": "contract"},
            )

        pagare_url = payload.get("pagarePdfBlobUrl", "")
        pagare_b64 = payload.get("pagarePdfBase64", "")
        if pagare_b64 and not pagare_url:
            uid = str(uuid.uuid4())[:8]
            blob_path = "clients/" + str(now.year) + "/" + str(now.month).zfill(2) + "/pagare_" + ts + "_" + uid + ".pdf"
            pagare_url = _upload_base64_to_blob(
                pagare_b64, blob_path, "application/pdf",
                {"companyId": str(payload.get("companyId", "0")), "type": "pagare"},
            )

        # Signature match: crop from the front ID photo (client-side, only
        # for documentType === 'INE' — see signatureCrop.ts) vs. the
        # signature captured on-screen at this same step. Both optional —
        # if either is missing, no comparison is attempted and the
        # existing manual-review flow (staff visually checking the
        # captures) is the only fallback, same as every other field this
        # OCR/vision pipeline can't guarantee.
        id_signature_url = payload.get("idSignatureCropBlobUrl", "")
        id_signature_b64 = payload.get("idSignatureCropBase64", "")
        if id_signature_b64 and not id_signature_url:
            uid = str(uuid.uuid4())[:8]
            blob_path = "clients/" + str(now.year) + "/" + str(now.month).zfill(2) + "/id_signature_" + ts + "_" + uid + ".png"
            id_signature_url = _upload_base64_to_blob(
                id_signature_b64, blob_path, "image/png",
                {"companyId": str(payload.get("companyId", "0")), "type": "id_signature_crop"},
            )

        contract_signature_url = payload.get("contractSignatureBlobUrl", "")
        contract_signature_b64 = payload.get("contractSignatureBase64", "")
        if contract_signature_b64 and not contract_signature_url:
            uid = str(uuid.uuid4())[:8]
            blob_path = "clients/" + str(now.year) + "/" + str(now.month).zfill(2) + "/contract_signature_" + ts + "_" + uid + ".png"
            contract_signature_url = _upload_base64_to_blob(
                contract_signature_b64, blob_path, "image/png",
                {"companyId": str(payload.get("companyId", "0")), "type": "contract_signature"},
            )

        match_result = None
        if id_signature_b64 and contract_signature_b64:
            try:
                from modules.signatureMatching import compare_signatures
                id_sig_bytes = base64.b64decode(
                    id_signature_b64.split(",", 1)[1] if "," in id_signature_b64 else id_signature_b64
                )
                contract_sig_bytes = base64.b64decode(
                    contract_signature_b64.split(",", 1)[1] if "," in contract_signature_b64 else contract_signature_b64
                )
                match_result = compare_signatures(id_sig_bytes, contract_sig_bytes)
            except Exception as e:
                # Advisory data only — a comparison failure shouldn't block
                # contract submission, the signatures are still saved above.
                print(f"[clientFaceRecognitions] signature comparison failed: {e}")
                match_result = None

        client_face_recognition_id = payload.get("clientFaceRecognitionId")
        record = {
            "action":              2 if client_face_recognition_id else 1,
            "companyId":           payload.get("companyId"),
            "clientId":            payload.get("clientId"),
            "documentType":        payload.get("documentType"),
            "idFrontImageBlobUrl": payload.get("idFrontImageBlobUrl"),
            "idBackImageBlobUrl":  payload.get("idBackImageBlobUrl"),
            "clientSelfieBlobUrl": payload.get("clientSelfieBlobUrl"),
            "confidenceScore":     payload.get("confidenceScore", 0.0),
            "isVerified":          payload.get("isVerified", False),
            "nombre":              payload.get("nombre"),
            "domicilio":           payload.get("domicilio"),
            "curp":                payload.get("curp"),
            "claveElector":        payload.get("claveElector"),
            "fechaNacimiento":     payload.get("fechaNacimiento"),
            "contractAccepted":    payload.get("contractAccepted", False),
            "contractPdfBlobUrl":  contract_url,
            "contractAcceptedAt":  payload.get("contractAcceptedAt"),
            "pagareAccepted":      payload.get("pagareAccepted", False),
            "pagarePdfBlobUrl":    pagare_url,
            "hasPhysicalPagare":   payload.get("hasPhysicalPagare", False),
            "idSignatureCropBlobUrl":  id_signature_url,
            "contractSignatureBlobUrl": contract_signature_url,
            "userId":              payload.get("userId"),
        }
        if match_result and match_result.get("reason") == "ok":
            record["signatureMatchScore"]  = match_result["matchScore"]
            record["signatureMatchPassed"] = match_result["matchPassed"]
            record["signatureMatchedAt"]   = now.isoformat()
        if client_face_recognition_id:
            record["clientFaceRecognitionId"] = client_face_recognition_id

        json_file = {"clientFaceRecognitions": [record]}
        sp_response = clientFaceRecognitions_sp(json_file)   # reuse CRUD SP for persistence

        if match_result is not None:
            # Surface the match result in this same response so the
            # frontend can show it without a second round trip — advisory
            # only, doesn't affect whether the SP call above succeeded.
            content = json.loads(sp_response.body)
            content["signatureMatch"] = match_result
            return JSONResponse(content=content, status_code=sp_response.status_code)

        return sp_response
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
