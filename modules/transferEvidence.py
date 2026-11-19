from fastapi.responses import JSONResponse
from databases import connection
import json
import threading
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


REVIEW_STATUSES = {"NEEDS_REVIEW", "INVALID"}


def _maybe_push_evidence_review(json_file: dict, result) -> None:
    """RFC-014 core push: when the AI verdict saved by action 'validate' is not
    VALID, tell the borrower to check the receipt before confirming. Background,
    never raises. Was sent by the app (P2PLendingPage / LoanDetailPage) before."""
    item = (json_file.get("transferEvidence") or [{}])[0] if isinstance(json_file, dict) else {}
    if item.get("action") != "validate" or str(item.get("validationStatus") or "").upper() not in REVIEW_STATUSES:
        return
    if isinstance(result, dict) and result.get("error"):
        return
    threading.Thread(target=_send_evidence_review, args=(item.get("companyId"), item.get("transferEvidenceId")),
                     daemon=True).start()


def _send_evidence_review(company_id, evidence_id) -> None:
    try:
        import asyncio
        from modules.fundingTransactions import _sp_raw
        from modules.loanPush import push_to_client
        evidence = json.loads(transfer_evidence_sp({"transferEvidence": [{
            "action": "one", "companyId": company_id, "transferEvidenceId": evidence_id}]}).body)
        if not isinstance(evidence, dict) or evidence.get("referenceType") != "FUNDING":
            return
        ft = _sp_raw({"fundingTransactions": [{
            "action": "one", "companyId": company_id, "fundingTransactionId": evidence.get("referenceId")}]})
        if not ft.get("borrowerClientId"):
            return
        asyncio.run(push_to_client(company_id, ft["borrowerClientId"], "funding_evidence_review",
                                   amount=ft.get("amountMXN"), loanId=ft.get("loanId"),
                                   fundingTransactionId=ft.get("fundingTransactionId")))
    except Exception as e:
        print(f"[transferEvidence] review push failed: {e}")


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
        result = json.loads(json_result)
        _maybe_push_evidence_review(json_file, result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
