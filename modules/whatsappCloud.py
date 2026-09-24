"""
WhatsApp Cloud API (Meta, direct — no Twilio/BSP in between).

- verify_signature(): every webhook POST is HMAC-SHA256 signed with the Meta
  app secret (X-Hub-Signature-256). Fails closed: no secret configured means
  nothing is accepted.
- send_text(): free-form text reply. Only delivered inside the 24h customer
  service window (the customer wrote to us in the last 24h) — outside it Meta
  requires an approved template.
- handle_webhook(): parses inbound messages and logs them through the same
  sp_whatsapp_messages the Twilio webhook already uses.

Env vars:
  WA_VERIFY_TOKEN      any string; must match "Verify token" in the Meta dashboard
  WA_APP_SECRET        Meta app → App settings → Basic → App secret
  WA_ACCESS_TOKEN      System User permanent token (the dashboard one lasts 24h)
  WA_PHONE_NUMBER_ID   from WhatsApp → API Setup
  WA_GRAPH_VERSION     default v25.0
"""

import hashlib
import hmac
import logging
import os
import re
from typing import Any, Dict, List

import httpx

from modules.whatsapp import log_message_to_database
from observability.integrations import timed_integration

logger = logging.getLogger(__name__)

GRAPH_VERSION = os.getenv("WA_GRAPH_VERSION", "v25.0")


def verify_signature(raw_body: bytes, signature_header: str | None) -> bool:
    app_secret = os.getenv("WA_APP_SECRET", "")
    if not app_secret:
        logger.error("[whatsappCloud] WA_APP_SECRET not set — rejecting webhook")
        return False
    if not signature_header or not signature_header.startswith("sha256="):
        return False
    expected = hmac.new(app_secret.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature_header.removeprefix("sha256="))


def normalize_mx_number(wa_id: str) -> str:
    """Meta reports Mexican mobiles as 521XXXXXXXXXX (legacy mobile '1'),
    but sends only reliably to 52XXXXXXXXXX. Returns digits only, no '+'."""
    digits = re.sub(r"\D", "", wa_id or "")
    if digits.startswith("521") and len(digits) == 13:
        return "52" + digits[3:]
    return digits


def send_text(to: str, body: str) -> Dict[str, Any]:
    token = os.getenv("WA_ACCESS_TOKEN")
    phone_number_id = os.getenv("WA_PHONE_NUMBER_ID")
    if not token or not phone_number_id:
        raise ValueError("Missing WA_ACCESS_TOKEN / WA_PHONE_NUMBER_ID environment variables.")

    to_digits = normalize_mx_number(to)
    request_body = {
        "messaging_product": "whatsapp",
        "recipient_type": "individual",
        "to": to_digits,
        "type": "text",
        "text": {"preview_url": False, "body": body},
    }
    url = f"https://graph.facebook.com/{GRAPH_VERSION}/{phone_number_id}/messages"
    with timed_integration("whatsapp_cloud", "send_text", request={"to": to_digits}) as span:
        resp = httpx.post(url, json=request_body,
                          headers={"Authorization": f"Bearer {token}"}, timeout=15.0)
        span.http_status = resp.status_code
        data = resp.json()
        span.response = data
        if resp.status_code >= 400:
            raise RuntimeError(f"WhatsApp Cloud send failed ({resp.status_code}): {data}")

    message_id = (data.get("messages") or [{}])[0].get("id")
    logger.info("[whatsappCloud] sent | to=%s id=%s", to_digits, message_id)
    return {"channel": "whatsapp", "to": to_digits, "provider": "meta", "messageId": message_id}


def _extract_inbound(payload: dict) -> List[Dict[str, Any]]:
    """Flattens Meta's entry[].changes[].value.messages[] into simple dicts.
    Status updates (sent/delivered/read) arrive in value.statuses and are
    skipped here."""
    out = []
    for entry in payload.get("entry") or []:
        for change in entry.get("changes") or []:
            if change.get("field") != "messages":
                continue
            value = change.get("value") or {}
            names = {c.get("wa_id"): (c.get("profile") or {}).get("name")
                     for c in value.get("contacts") or []}
            for msg in value.get("messages") or []:
                msg_type = msg.get("type")
                if msg_type == "text":
                    text = (msg.get("text") or {}).get("body", "")
                elif msg_type == "button":
                    text = (msg.get("button") or {}).get("text", "")
                elif msg_type == "interactive":
                    inter = msg.get("interactive") or {}
                    reply = inter.get("button_reply") or inter.get("list_reply") or {}
                    text = reply.get("title", "")
                else:
                    text = f"[{msg_type}]"
                out.append({
                    "from": msg.get("from", ""),
                    "name": names.get(msg.get("from")),
                    "messageId": msg.get("id"),
                    "type": msg_type,
                    "text": text,
                })
    return out


def handle_webhook(payload: dict) -> None:
    """Runs in a background task — the route already answered Meta 200."""
    for msg in _extract_inbound(payload):
        logger.info("[whatsappCloud] inbound | from=%s type=%s id=%s",
                    msg["from"], msg["type"], msg["messageId"])
        try:
            log_message_to_database(
                phone_number="+" + normalize_mx_number(msg["from"]),
                message_body=msg["text"],
                response_body="",
                direction="inbound",
                status="received",
                action=1,
            )
        except Exception:
            logger.exception("[whatsappCloud] failed to log inbound message")
        # Next step: hand msg to the reservations agent and send_text() its reply.
