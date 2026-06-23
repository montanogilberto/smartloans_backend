"""
Signature Upload Route
Accepts a base64 PNG of the borrower's digital signature,
uploads to Azure Blob Storage, returns the permanent URL.
The URL is then saved to clientFaceRecognitions.pagarePdfBlobUrl.
"""
from fastapi import APIRouter
from fastapi.responses import JSONResponse
from azure.storage.blob import BlobServiceClient, ContentSettings
from datetime import datetime
import base64
import uuid
import os

router = APIRouter(prefix="/signatures", tags=["Signatures"])

_CLIENTS_CONTAINER    = os.getenv("CLIENTS_CONTAINER_NAME", "clients")
_ACCOUNT_URL_FALLBACK = os.getenv("AZURE_STORAGE_ACCOUNT_URL_FALLBACK", "")


def _upload_signature(b64_data: str, client_id: int, company_id: int, doc_type: str) -> str:
    conn_str = os.getenv("AZURE_STORAGE_CONNECTION_STRING", "")
    if not conn_str:
        raise RuntimeError("Missing AZURE_STORAGE_CONNECTION_STRING env var")

    # Strip data-URI header if present
    if "," in b64_data:
        b64_data = b64_data.split(",", 1)[1]

    raw_bytes = base64.b64decode(b64_data)

    ts  = datetime.utcnow().strftime("%Y%m%d%H%M%S")
    uid = str(uuid.uuid4())[:8]
    now = datetime.utcnow()
    blob_path = (
        f"signatures/{now.year}/{str(now.month).zfill(2)}/"
        f"client{client_id}_{doc_type}_{ts}_{uid}.png"
    )

    service_client   = BlobServiceClient.from_connection_string(conn_str)
    container_client = service_client.get_container_client(_CLIENTS_CONTAINER)
    blob_client      = container_client.get_blob_client(blob_path)

    blob_client.upload_blob(
        raw_bytes,
        overwrite=True,
        content_settings=ContentSettings(content_type="image/png"),
        metadata={
            "clientId":  str(client_id),
            "companyId": str(company_id),
            "docType":   doc_type,
            "uploadedAt": datetime.utcnow().isoformat(),
        },
    )

    account_url = getattr(service_client, "url", None) or _ACCOUNT_URL_FALLBACK
    return account_url.rstrip("/") + "/" + _CLIENTS_CONTAINER + "/" + blob_path


@router.post(
    "/upload",
    summary="Upload digital signature PNG to Azure Blob Storage",
    description="""
Accepts a base64-encoded PNG of the borrower's digital signature drawn on the
SignaturePad canvas, uploads to Azure Blob (clients/signatures/ container),
and returns the permanent public URL.

Save the returned blobUrl to clientFaceRecognitions.pagarePdfBlobUrl.

Body: {
  "clientId":    int,
  "companyId":   int,
  "signatureB64": str,   -- base64 PNG (with or without data:image/png;base64, prefix)
  "docType":     str     -- "pagare" | "contract"
}
Returns: { "blobUrl": str, "docType": str, "uploadedAt": str }
""",
)
async def upload_signature(json: dict):
    client_id    = json.get("clientId")
    company_id   = json.get("companyId")
    signature_b64 = json.get("signatureB64", "")
    doc_type     = json.get("docType", "pagare")

    if not client_id or not signature_b64:
        return JSONResponse({"error": "clientId and signatureB64 required"}, status_code=400)

    try:
        blob_url = _upload_signature(
            signature_b64, int(client_id), int(company_id or 0), doc_type
        )
        return JSONResponse({
            "blobUrl":    blob_url,
            "docType":    doc_type,
            "uploadedAt": datetime.utcnow().isoformat(),
        }, status_code=200)

    except RuntimeError as e:
        # Blob not configured — return placeholder URL for dev
        if "AZURE_STORAGE_CONNECTION_STRING" in str(e):
            return JSONResponse({
                "blobUrl":    f"https://imageprofile.blob.core.windows.net/clients/signatures/client{client_id}_{doc_type}_dev.png",
                "docType":    doc_type,
                "uploadedAt": datetime.utcnow().isoformat(),
                "warning":    "Azure Blob not configured — placeholder URL returned",
            }, status_code=200)
        return JSONResponse({"error": str(e)}, status_code=500)

    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
