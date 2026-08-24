from fastapi.responses import JSONResponse
from databases import connection
import json
import uuid
from datetime import datetime

from modules.clientFaceRecognitions import (
    _upload_base64_to_blob, client_blob_path, BLOB_FOLDER_FUNDING_EVIDENCE,
)


def _conn():
    return connection()


async def upload_transfer_evidence_connector(payload: dict) -> JSONResponse:
    """Uploads a comprobante (SPEI transfer receipt) photo to Azure Blob
    Storage, same helpers/container as clientFaceRecognitions -- this is
    still a per-client asset (the declarer), just a different folder.
    Returns: { blobUrl }. The caller persists the URL via sp_transferEvidence
    'create' (evidenceFileUrl) separately -- this endpoint only uploads bytes."""
    try:
        company_id = payload.get("companyId", "0")
        client_id  = payload.get("clientId", "0")
        image_b64  = payload.get("imageBase64", "")

        if not image_b64:
            return JSONResponse(content={"error": "imageBase64 is required"}, status_code=400)

        ts  = datetime.utcnow().strftime("%Y%m%d%H%M%S")
        uid = str(uuid.uuid4())[:8]
        blob_path = client_blob_path(client_id, BLOB_FOLDER_FUNDING_EVIDENCE, f"evidence_{ts}_{uid}.jpg")

        blob_url = _upload_base64_to_blob(
            image_b64, blob_path, "image/jpeg",
            {"companyId": str(company_id), "clientId": str(client_id)},
        )

        return JSONResponse(content={"blobUrl": blob_url}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def transfer_evidence_sp(json_file: dict):
    """create | list | one via sp_transferEvidence. Stores PROOF a direct
    SPEI transfer happened outside SmartLoans (clave de rastreo, bank,
    optional attachment + hash) -- see sql/sp_transferEvidence.sql. Never
    moves money itself."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_transferEvidence] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        row = cursor.fetchone()
        json_result = row[0] if row and row[0] else '{"error":"no result"}'
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
