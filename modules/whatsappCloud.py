"""
WhatsApp Cloud API (Meta, direct — no Twilio/BSP in between).

- verify_signature(): every webhook POST is HMAC-SHA256 signed with the Meta
  app secret (X-Hub-Signature-256). Fails closed: no secret configured means
  nothing is accepted.
- send_text(): free-form text reply. Only delivered inside the 24h customer
  service window (the customer wrote to us in the last 24h) — outside it Meta
  requires an approved template.
- handle_webhook(): resolves the number each message arrived on
  (value.metadata.phone_number_id) to its company/branch through
  whatsappChannels (modules/whatsappChannels.py), logs the message through
  the same sp_whatsapp_messages the Twilio webhook already uses, and sends
  the reservations bot's reply FROM that same number.
  Messages to numbers not registered in whatsappChannels are logged and
  ignored.

One Meta app serves every company: the env vars below belong to the app,
not to a company. Per-number data lives in dbo.whatsappChannels.

Env vars:
  WA_VERIFY_TOKEN      any string; must match "Verify token" in the Meta dashboard
  WA_APP_SECRET        Meta app → App settings → Basic → App secret
  WA_ACCESS_TOKEN      System User permanent token — covers every number in
                       our Meta portfolio (channel.accessTokenRef overrides)
  WA_GRAPH_VERSION     default v25.0
"""

import hashlib
import hmac
import logging
import os
import re
from typing import Any, Dict, List

import httpx

from modules import whatsappChannels, whatsappReservations
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


def send_text(channel: dict, to: str, body: str) -> Dict[str, Any]:
    """Sends from the channel's number (the one the customer wrote to)."""
    token = whatsappChannels.access_token(channel)
    phone_number_id = channel["phoneNumberId"]

    to_digits = normalize_mx_number(to)
    request_body = {
        "messaging_product": "whatsapp",
        "recipient_type": "individual",
        "to": to_digits,
        "type": "text",
        "text": {"preview_url": False, "body": body},
    }
    url = f"https://graph.facebook.com/{GRAPH_VERSION}/{phone_number_id}/messages"
    with timed_integration("whatsapp_cloud", "send_text",
                           request={"to": to_digits, "phoneNumberId": phone_number_id}) as span:
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
            phone_number_id = (value.get("metadata") or {}).get("phone_number_id")
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
                    "phoneNumberId": phone_number_id,
                    "from": msg.get("from", ""),
                    "name": names.get(msg.get("from")),
                    "messageId": msg.get("id"),
                    "type": msg_type,
                    "text": text,
                })
    return out


def _log_statuses(payload: dict) -> None:
    """Outbound delivery receipts. A send that Meta accepted (200 + wamid) can
    still fail later — e.g. 131047 outside the 24h window, 131042 no payment
    method — and this webhook is the only place Meta reports why."""
    for entry in payload.get("entry") or []:
        for change in entry.get("changes") or []:
            if change.get("field") != "messages":
                continue
            for st in (change.get("value") or {}).get("statuses") or []:
                if st.get("status") == "failed":
                    logger.warning("[whatsappCloud] send failed | to=%s id=%s errors=%s",
                                   st.get("recipient_id"), st.get("id"), st.get("errors"))
                else:
                    logger.info("[whatsappCloud] status | to=%s id=%s status=%s",
                                st.get("recipient_id"), st.get("id"), st.get("status"))


def _pause_bot_on_staff_replies(payload: dict) -> None:
    """Coexistence: a message staff send from the WhatsApp Business app comes
    back as field "smb_message_echoes". The bot steps aside in that chat."""
    for entry in payload.get("entry") or []:
        for change in entry.get("changes") or []:
            if change.get("field") != "smb_message_echoes":
                continue
            value = change.get("value") or {}
            channel = whatsappChannels.get_channel((value.get("metadata") or {}).get("phone_number_id"))
            if not channel:
                continue
            for echo in value.get("message_echoes") or []:
                customer = "+" + normalize_mx_number(echo.get("to", ""))
                logger.info("[whatsappCloud] staff replied from app | channel=%s to=%s",
                            channel["channelId"], customer)
                whatsappReservations.pause_for_staff(channel, customer)


def _handle_message(msg: dict) -> None:
    channel = whatsappChannels.get_channel(msg["phoneNumberId"])
    if not channel:
        logger.warning("[whatsappCloud] message to unregistered number | phoneNumberId=%s — "
                       "add it with POST /whatsapp/channels", msg["phoneNumberId"])
        return

    phone = "+" + normalize_mx_number(msg["from"])
    logger.info("[whatsappCloud] inbound | channel=%s company=%s branch=%s from=%s type=%s id=%s",
                channel["channelId"], channel["companyId"], channel.get("branchId"),
                phone, msg["type"], msg["messageId"])
    try:
        log_message_to_database(phone_number=phone, message_body=msg["text"], response_body="",
                                direction="inbound", status="received", action=1)
    except Exception:
        logger.exception("[whatsappCloud] failed to log inbound message")

    if not channel.get("botEnabled"):
        return
    reply = whatsappReservations.reply_to(channel, phone, msg["name"], msg["text"])
    if not reply:
        return
    try:
        send_text(channel, phone, reply)
        log_message_to_database(phone_number=phone, message_body=reply, response_body="",
                                direction="outbound", status="sent", action=1)
    except Exception:
        logger.exception("[whatsappCloud] failed to send bot reply | to=%s", phone)


def handle_webhook(payload: dict) -> None:
    """Runs in a background task — the route already answered Meta 200.
    One bad message (DB down, agent error) must not drop the rest."""
    _log_statuses(payload)
    try:
        _pause_bot_on_staff_replies(payload)
    except Exception:
        logger.exception("[whatsappCloud] failed to process staff echoes")
    for msg in _extract_inbound(payload):
        try:
            _handle_message(msg)
        except Exception:
            logger.exception("[whatsappCloud] failed to handle message | id=%s", msg.get("messageId"))
