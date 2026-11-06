"""
A client sends the photo of a transfer receipt over WhatsApp. The agent reads it,
the comprobante waits on the client's POS card, and staff get a push. Nothing is
credited here: only a person who saw the money in the company's account does that
(modules/walletTopUps.py).
"""
import asyncio
import base64
import json
import logging
import os
import uuid

import httpx

from modules import whatsappChannels
from modules.clientFaceRecognitions import BLOB_FOLDER_FUNDING_EVIDENCE, _upload_base64_to_blob, client_blob_path
from modules.pushNotifications import pushNotifications_sp
from modules.walletTopUps import create_pending_evidence
from modules.whatsappAssistant import _sp as assistant_sp
from observability.integrations import timed_integration
from observability.logger import log_workflow_step

logger = logging.getLogger(__name__)

AGENT_URL = os.environ.get("NEGOTIATION_AGENT_URL", "").rstrip("/")
GRAPH_VERSION = os.getenv("WA_GRAPH_VERSION", "v25.0")

_RECEIVED = ("Recibimos tu comprobante por {amount}. El equipo lo revisará y te abonará el saldo "
             "en cuanto vea la transferencia.")
_UNREADABLE = ("Recibí tu comprobante, pero no pude leer el total, la clave de rastreo o la fecha. "
               "¿Me lo mandas con una foto más clara?")
_NOT_REGISTERED = ("Recibí tu comprobante, pero este número no está registrado como cliente. "
                   "Muéstralo en caja y ahí te lo abonan.")
_DUPLICATE = "Ese comprobante ya lo tenemos registrado. El equipo lo está revisando."
_FAILED = "No pude procesar tu comprobante en este momento. Inténtalo en un rato o muéstralo en caja."


def _download(channel: dict, media_id: str) -> bytes:
    headers = {"Authorization": f"Bearer {whatsappChannels.access_token(channel)}"}
    with timed_integration("whatsapp_cloud", "download_media"):
        meta = httpx.get(f"https://graph.facebook.com/{GRAPH_VERSION}/{media_id}", headers=headers, timeout=20.0)
        meta.raise_for_status()
        media = httpx.get(meta.json()["url"], headers=headers, timeout=30.0)
        media.raise_for_status()
    return media.content


def _read(image_b64: str) -> dict:
    with timed_integration("loan_agents", "extract_transfer_evidence"):
        resp = httpx.post(f"{AGENT_URL}/transfers/extract-evidence", json={"evidenceBase64": image_b64}, timeout=60.0)
        resp.raise_for_status()
    return resp.json()


def _push_staff(channel: dict, client_id: int, amount: float) -> None:
    try:
        asyncio.run(pushNotifications_sp({"pushNotifications": [{
            "action": 1,
            "companyId": channel["companyId"],
            "title": "🧾 Comprobante por revisar",
            "message": f"Un cliente envió un comprobante por ${amount:,.2f} MXN por WhatsApp.",
            "notificationType": "Info",
            "priority": "High",
            "targetType": "Company",
            "targetCompanyId": channel["companyId"],
            "navigationRoute": f"/client-pos/{client_id}",
            "payloadJson": json.dumps({"type": "TransferEvidence", "clientId": client_id}),
        }]}))
    except Exception:
        logger.exception("[whatsappEvidence] staff push failed | client=%s", client_id)


def handle_image(channel: dict, phone: str, media_id: str | None) -> str | None:
    """The reply for a receipt, or None when the image isn't one (the agent then
    answers it like any other message)."""
    if not media_id or not AGENT_URL:
        return None
    try:
        image_b64 = base64.b64encode(_download(channel, media_id)).decode()
        reading = _read(image_b64)
    except Exception:
        logger.exception("[whatsappEvidence] reading failed")
        return None
    if not reading.get("isTransferReceipt"):
        return None
    amount, clave, date = reading.get("amountMXN"), reading.get("claveRastreo"), reading.get("transferDate")
    if not (amount and clave and date):
        return _UNREADABLE

    try:
        found = (assistant_sp("sp_whatsappCustomerRewards", {"customerRewards": [
            {"companyId": channel["companyId"], "phone": phone}]}).get("result") or [{}])[0]
        if found.get("status") != "found" or not found.get("clientId"):
            return _NOT_REGISTERED
        client_id = int(found["clientId"])
        path = client_blob_path(client_id, BLOB_FOLDER_FUNDING_EVIDENCE, f"evidence_wa_{uuid.uuid4().hex[:12]}.jpg")
        url = _upload_base64_to_blob(image_b64, path, "image/jpeg",
                                     {"companyId": str(channel["companyId"]), "clientId": str(client_id)})
        evidence = create_pending_evidence({
            "companyId": channel["companyId"], "clientId": client_id, "claveRastreo": clave,
            "transferDate": date, "bankFrom": reading.get("bankFrom") or None, "amountMXN": amount,
            "evidenceFileUrl": url,
        })
    except Exception:
        logger.exception("[whatsappEvidence] saving failed")
        return _FAILED
    if evidence.get("error"):
        if "UQ_transferEvidence" in str(evidence["error"]):
            return _DUPLICATE
        logger.error("[whatsappEvidence] evidence refused: %s", evidence["error"])
        return _FAILED

    _push_staff(channel, client_id, float(amount))
    log_workflow_step("WhatsApp Evidence Received", workflow_name="money_trail", action="wallet_topup",
                      entity="transferEvidence", entity_id=evidence.get("transferEvidenceId"),
                      message=f"${float(amount):,.2f} MXN pending staff")
    return _RECEIVED.format(amount=f"${float(amount):,.2f}")
