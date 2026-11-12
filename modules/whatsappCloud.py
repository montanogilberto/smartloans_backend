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

import asyncio
import hashlib
import hmac
import logging
import time
import os
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

import httpx

from fastapi.responses import JSONResponse

from modules import clientContactPreferences, marketingLeadAttributions, whatsappChannels, whatsappReservations
from modules import whatsappEvidence
from modules import whatsappMessageDeliveries
from modules.whatsapp import log_message_to_database, log_outbound_message
from modules.whatsappAssistant import _sp as assistant_sp
from observability.integrations import timed_integration
from observability.logger import log_workflow_step

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
    logger.info("[whatsappCloud] sent | to=…%s id=%s", to_digits[-4:], message_id)
    return {"channel": "whatsapp", "to": to_digits, "provider": "meta", "messageId": message_id}


def send_image(channel: dict, to: str, image: bytes, caption: str,
               filename: str = "image.png", mime_type: str = "image/png") -> Dict[str, Any]:
    """Uploads the image to Meta's media store and sends it from the
    channel's number. No public URL involved, so private data (a client's
    QR) is never left on an open link."""
    token = whatsappChannels.access_token(channel)
    phone_number_id = channel["phoneNumberId"]
    to_digits = normalize_mx_number(to)
    headers = {"Authorization": f"Bearer {token}"}
    base = f"https://graph.facebook.com/{GRAPH_VERSION}/{phone_number_id}"

    with timed_integration("whatsapp_cloud", "upload_media",
                           request={"phoneNumberId": phone_number_id, "mimeType": mime_type}) as span:
        resp = httpx.post(f"{base}/media", headers=headers, timeout=20.0,
                          data={"messaging_product": "whatsapp", "type": mime_type},
                          files={"file": (filename, image, mime_type)})
        span.http_status = resp.status_code
        data = resp.json()
        span.response = data
        if resp.status_code >= 400 or not data.get("id"):
            raise RuntimeError(f"WhatsApp Cloud media upload failed ({resp.status_code}): {data}")
    media_id = data["id"]

    request_body = {
        "messaging_product": "whatsapp",
        "recipient_type": "individual",
        "to": to_digits,
        "type": "image",
        "image": {"id": media_id, "caption": caption},
    }
    with timed_integration("whatsapp_cloud", "send_image",
                           request={"to": to_digits, "phoneNumberId": phone_number_id}) as span:
        resp = httpx.post(f"{base}/messages", json=request_body, headers=headers, timeout=15.0)
        span.http_status = resp.status_code
        data = resp.json()
        span.response = data
        if resp.status_code >= 400:
            raise RuntimeError(f"WhatsApp Cloud image send failed ({resp.status_code}): {data}")

    message_id = (data.get("messages") or [{}])[0].get("id")
    logger.info("[whatsappCloud] sent image | to=%s id=%s", to_digits, message_id)
    return {"channel": "whatsapp", "to": to_digits, "provider": "meta", "messageId": message_id}


def show_typing(channel: dict, message_id: str | None) -> None:
    """Marks the customer's message as read (blue ticks) and shows "escribiendo…"
    until our reply is sent (Meta hides it after ~25 s). Best effort: a
    failure here must never block the reply."""
    if not message_id:
        return
    try:
        token = whatsappChannels.access_token(channel)
        url = f"https://graph.facebook.com/{GRAPH_VERSION}/{channel['phoneNumberId']}/messages"
        resp = httpx.post(url, json={"messaging_product": "whatsapp", "status": "read",
                                     "message_id": message_id,
                                     "typing_indicator": {"type": "text"}},
                          headers={"Authorization": f"Bearer {token}"}, timeout=5.0)
        if resp.status_code >= 400:
            logger.warning("[whatsappCloud] typing indicator failed (%s): %s",
                           resp.status_code, resp.text[:300])
    except Exception:
        logger.exception("[whatsappCloud] typing indicator failed")


# ── Outbound templates ──────────────────────────────────────────────────────
# Messages WE start (receipts, OTP, offers, reservations) reach people who
# haven't written in 24h, so Meta only delivers them as approved templates.
# Template texts to register: docs/whatsapp-templates.md

TEMPLATE_LANG = os.getenv("WA_TEMPLATE_LANG", "es_MX")


def outbound_channel() -> dict | None:
    """The number app-initiated messages go out from (WA_SENDER_PHONE_NUMBER_ID).
    It is Meta's "Phone number ID" (digits, e.g. 1330937783442101), NOT the
    phone number. None → not configured: send_whatsapp raises (Twilio is
    disabled) and notificationDispatch moves on to SMS. A DB hiccup on the
    channel lookup must not block a send: WA_ACCESS_TOKEN covers every number."""
    phone_number_id = os.getenv("WA_SENDER_PHONE_NUMBER_ID")
    if not phone_number_id:
        return None
    try:
        return whatsappChannels.get_channel(phone_number_id) or {"phoneNumberId": phone_number_id}
    except Exception:
        logger.exception("[whatsappCloud] sender channel lookup failed — using WA_ACCESS_TOKEN")
        return {"phoneNumberId": phone_number_id}


def _param_text(value: Any) -> str:
    """Meta rejects template params with newlines, tabs or 4+ spaces in a row
    (error 132018), and empty params (131008)."""
    text = re.sub(r"[\r\n\t]+", " · ", str(value if value is not None else "")).strip(" ·")
    text = re.sub(r" {4,}", "   ", text)
    return text or "—"


def send_template(channel: dict, to: str, name: str, params: List[Any],
                  button_param: str | None = None) -> Dict[str, Any]:
    """Sends approved template `name` with body params {{1}}..{{n}}.
    button_param fills the copy-code button of AUTHENTICATION templates."""
    token = whatsappChannels.access_token(channel)
    phone_number_id = channel["phoneNumberId"]

    to_digits = normalize_mx_number(to)
    components: List[Dict[str, Any]] = [{
        "type": "body",
        "parameters": [{"type": "text", "text": _param_text(p)} for p in params],
    }]
    if button_param is not None:
        components.append({"type": "button", "sub_type": "url", "index": "0",
                           "parameters": [{"type": "text", "text": button_param}]})
    request_body = {
        "messaging_product": "whatsapp",
        "recipient_type": "individual",
        "to": to_digits,
        "type": "template",
        "template": {"name": name, "language": {"code": TEMPLATE_LANG}, "components": components},
    }
    url = f"https://graph.facebook.com/{GRAPH_VERSION}/{phone_number_id}/messages"
    # Params are left out of the trace: the OTP template carries the code.
    with timed_integration("whatsapp_cloud", "send_template",
                           request={"to": to_digits, "phoneNumberId": phone_number_id,
                                    "template": name}) as span:
        resp = httpx.post(url, json=request_body,
                          headers={"Authorization": f"Bearer {token}"}, timeout=15.0)
        span.http_status = resp.status_code
        data = resp.json()
        span.response = data
        if resp.status_code >= 400:
            raise RuntimeError(f"WhatsApp Cloud template {name} failed ({resp.status_code}): {data}")

    message_id = (data.get("messages") or [{}])[0].get("id")
    logger.info("[whatsappCloud] template sent | to=…%s template=%s id=%s", to_digits[-4:], name, message_id)
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
                elif msg_type == "location":
                    # A shared pin. The agent gets its place name/address as text;
                    # the coordinates stay here (see whatsappReservations.reply_to).
                    loc = msg.get("location") or {}
                    label = ", ".join(x for x in (loc.get("name"), loc.get("address")) if x)
                    text = f"[ubicación compartida] {label}".strip()
                else:
                    text = f"[{msg_type}]"
                out.append({
                    "phoneNumberId": phone_number_id,
                    "from": msg.get("from", ""),
                    "name": names.get(msg.get("from")),
                    "messageId": msg.get("id"),
                    "type": msg_type,
                    "text": text,
                    "mediaId": (msg.get("image") or {}).get("id"),
                    "referral": msg.get("referral"),
                    "location": msg.get("location") if msg_type == "location" else None,
                    "timestamp": msg.get("timestamp"),
                })
    return out


def _record_outbound(*, channel: dict, phone_number: str, message_body: str, response_body: str,
                     status: str, wamid: str | None, sender_kind: str) -> None:
    """After Meta accepted a send: log it to whatsappMessages (the POS bubble) and
    open its delivery receipt (status 'accepted') linked to that row, so the
    webhook's sent/delivered/read can turn into ticks. Never raises."""
    message_id = log_outbound_message({"phoneNumber": phone_number, "messageBody": message_body,
                                       "responseBody": response_body, "direction": "outbound",
                                       "status": status})
    if not wamid or not channel:
        return
    whatsappMessageDeliveries.upsert_delivery({
        "providerMessageId": wamid, "whatsappMessageId": message_id,
        "companyId": channel.get("companyId"), "channelId": channel.get("channelId"),
        "senderKind": sender_kind, "status": "accepted",
    })


def _record_status(channel: dict | None, st: dict) -> None:
    """One Meta receipt (value.statuses[]) -> whatsappMessageDeliveries. Receipts of
    numbers we don't know are skipped (no company to file them under)."""
    if not channel or st.get("status") not in ("sent", "delivered", "read", "failed"):
        return
    err = (st.get("errors") or [{}])[0]
    whatsappMessageDeliveries.upsert_delivery({
        "providerMessageId": st.get("id"), "companyId": channel.get("companyId"),
        "channelId": channel.get("channelId"), "status": st.get("status"),
        "statusTimestamp": st.get("timestamp"),
        "errorCode": str(err["code"]) if err.get("code") is not None else None,
        "errorTitle": err.get("title") or err.get("message"),
    })


def _log_statuses(payload: dict) -> None:
    """Outbound delivery receipts. A send that Meta accepted (200 + wamid) can
    still fail later — e.g. 131047 outside the 24h window, 131042 no payment
    method — and this webhook is the only place Meta reports why."""
    for entry in payload.get("entry") or []:
        for change in entry.get("changes") or []:
            if change.get("field") != "messages":
                continue
            value = change.get("value") or {}
            statuses = value.get("statuses") or []
            channel = None
            if statuses:
                try:
                    channel = whatsappChannels.get_channel((value.get("metadata") or {}).get("phone_number_id"))
                except Exception:
                    logger.exception("[whatsappCloud] status: channel lookup failed")
            for st in statuses:
                # Phone masked to its last 4 digits: the full number is PII.
                to = "…" + str(st.get("recipient_id") or "")[-4:]
                if st.get("status") == "failed":
                    logger.warning("[whatsappCloud] send failed | to=%s id=%s errors=%s",
                                   to, st.get("id"), st.get("errors"))
                else:
                    logger.info("[whatsappCloud] status | to=%s id=%s status=%s",
                                to, st.get("id"), st.get("status"))
                try:
                    _record_status(channel, st)
                except Exception:
                    logger.exception("[whatsappCloud] delivery receipt not recorded | id=%s", st.get("id"))
                err = (st.get("errors") or [{}])[0]
                _update_dispatch(st.get("id"), st.get("status"),
                                 err.get("code"), err.get("title") or err.get("message"))


def _update_dispatch(wamid: str | None, status: str | None,
                     error_code=None, error_message=None) -> None:
    """delivered/read -> the notification dispatch sent with this wamid becomes
    "confirmed"; failed -> "failed". sent is in-flight and ignored. Runs in the
    webhook's background task (its own thread), so a fresh event loop is fine.
    Never raises: a dispatch-log hiccup must not stop the inbound messages."""
    if not wamid or status not in ("delivered", "read", "failed"):
        return
    try:
        # Lazy: notificationDispatch -> ticket_notifications -> whatsappCloud.
        from modules.notificationDispatch import apply_provider_status
        outcome = asyncio.run(apply_provider_status(
            wamid, status,
            error_code=str(error_code) if error_code is not None else None,
            error_message=error_message,
        ))
        logger.info("[whatsappCloud] dispatch status | id=%s status=%s -> %s", wamid, status, outcome)
    except Exception:
        logger.exception("[whatsappCloud] dispatch status update failed | id=%s", wamid)


def _log_staff_echoes(payload: dict) -> None:
    """Coexistence: a message staff send from the WhatsApp Business app comes
    back as field "smb_message_echoes". It is logged so the POS inbox shows it;
    the agent keeps answering the chat (it is never paused)."""
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
                text = (echo.get("text") or {}).get("body")
                if text:
                    # So POS › Conversaciones shows what staff answered from the app too.
                    try:
                        log_message_to_database(phone_number=customer, message_body=text, response_body="",
                                                direction="outbound", status="staff_app", action=1)
                    except Exception:
                        logger.exception("[whatsappCloud] failed to log staff echo")


def _sent_at(timestamp: Any) -> str | None:
    """Meta's epoch seconds as UTC; None lets the SP use the current time."""
    try:
        return datetime.fromtimestamp(int(timestamp), timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    except (TypeError, ValueError, OverflowError, OSError):
        return None


def _record_ad_referral(channel: dict, phone: str, msg: dict) -> None:
    """The ad that opened this chat. Meta sends it only on the first message
    after the click, so it is saved now; a failure must never cost the
    customer their reply. companyId comes from the channel, never the ad."""
    referral = msg.get("referral")
    if not referral:
        return
    try:
        marketingLeadAttributions.record_referral({"marketingLeadAttributions": [{
            "action": 1,
            "companyId": channel["companyId"],
            "provider": "meta",
            "conversionChannel": "whatsapp",
            "channelId": channel["channelId"],
            "customerPhone": phone,
            "externalEventId": msg["messageId"],
            "sourceType": referral.get("source_type"),
            "sourceId": referral.get("source_id"),
            "ctwaClid": referral.get("ctwa_clid"),
            "headline": (referral.get("headline") or "")[:255] or None,
            "body": (referral.get("body") or "")[:1000] or None,
            "sourceUrl": (referral.get("source_url") or "")[:500] or None,
            "mediaType": referral.get("media_type"),
            "rawReferral": referral,
            "referredAt": _sent_at(msg.get("timestamp")),
        }]})
    except Exception:
        logger.warning("[whatsappCloud] ad referral not recorded | id=%s", msg.get("messageId"))


# Meta delivers at least once: a retry of a message already answered must not
# get a second reply. In process only — another App Service instance can still
# see a retry, so this cuts duplicates, it doesn't guarantee none.
SEEN_MESSAGE_SECONDS = 3600
_seen_messages: dict[str, float] = {}


def _first_delivery(message_id: str | None) -> bool:
    if not message_id:
        return True
    now = time.time()
    if len(_seen_messages) > 5000:
        for key in [k for k, t in _seen_messages.items() if now - t > SEEN_MESSAGE_SECONDS]:
            del _seen_messages[key]
    if now - _seen_messages.get(message_id, 0) < SEEN_MESSAGE_SECONDS:
        return False
    _seen_messages[message_id] = now
    return True


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
    # Before the agent runs: it creates the conversation row isNewLead looks for.
    _record_ad_referral(channel, phone, msg)
    try:
        whatsappChannels.touch(channel["channelId"], phone)
    except Exception:
        logger.exception("[whatsappCloud] failed to mark the conversation's number")
    try:
        log_message_to_database(phone_number=phone, message_body=msg["text"], response_body="",
                                direction="inbound", status="received", action=1)
    except Exception:
        logger.exception("[whatsappCloud] failed to log inbound message")

    # Only the reply is skipped on a retry: the logging and the ad referral
    # above dedupe in their own SPs.
    if not _first_delivery(msg.get("messageId")):
        logger.info("[whatsappCloud] retry already answered | id=%s", msg.get("messageId"))
        return

    # BAJA/ALTA (marketing consent) is answered even when the bot is off: an
    # opt-out must always work, and it is never passed on to the agent.
    reply = clientContactPreferences.handle_keyword(channel["companyId"], phone, msg["text"])
    if reply is None:
        # A reaction (❤️ on a message) is not something to answer.
        if not channel.get("botEnabled") or msg["type"] == "reaction":
            return
        if msg["type"] == "image":
            show_typing(channel, msg["messageId"])
            reply = whatsappEvidence.handle_image(channel, phone, msg.get("mediaId"))
        if reply is None:
            reply = whatsappReservations.reply_to(channel, phone, msg["name"], msg["text"],
                                                  on_answering=lambda: show_typing(channel, msg["messageId"]),
                                                  ad_referral=msg.get("referral"),
                                                  location=msg.get("location"))
    if not reply:
        return
    try:
        sent = send_text(channel, phone, reply)
        _record_outbound(channel=channel, phone_number=phone, message_body=reply, response_body="",
                         status="sent", wamid=(sent or {}).get("messageId"), sender_kind="agent")
    except Exception:
        logger.exception("[whatsappCloud] failed to send bot reply | to=…%s", phone[-4:])


def handle_webhook(payload: dict) -> None:
    """Runs in a background task — the route already answered Meta 200.
    One bad message (DB down, agent error) must not drop the rest."""
    _log_statuses(payload)
    try:
        _log_staff_echoes(payload)
    except Exception:
        logger.exception("[whatsappCloud] failed to process staff echoes")
    for msg in _extract_inbound(payload):
        try:
            _handle_message(msg)
        except Exception:
            logger.exception("[whatsappCloud] failed to handle message | id=%s", msg.get("messageId"))


# ── Staff replies from the POS (Agente WhatsApp › Conversaciones) ───────────
STAFF_REPLY_MAX_CHARS = 4096  # Meta's text body limit
# Outside the 24 h window the text goes inside this approved template
# (docs/whatsapp-templates.md): {{1}} company, {{2}} the staff's message.
STAFF_TEMPLATE = "mensaje_negocio"
STAFF_TEMPLATE_MAX_CHARS = 900  # Meta caps a template body at 1024 with its fixed text
# Meta's customer-service window. Free-form text outside it is ACCEPTED by the
# API and only fails later (status 131047), so it is checked here, before sending.
_SERVICE_WINDOW = timedelta(hours=24)


def staff_reply(json_file: dict) -> JSONResponse:
    """POST /whatsapp/staffReply — a POS user answers a WhatsApp customer from the
    business number the customer wrote to. Logged to whatsappMessages as
    'staff_sent' (responseBody = "userId=<id>"). The agent keeps answering the
    chat — it is never paused.

    Body: { "whatsappStaffReply": [{ "companyId": int, "userId": int, "phone10": str, "body": str,
                                     "asTemplate"?: bool }] }
    200 { sent: true, messageId, atUtc, viaTemplate }
    400 bad input   404 no_channel (no number of this company has talked to the phone)
    409 outside_24h (the customer hasn't written in 24 h: Meta only allows templates)
    502 send_failed / template_failed (Meta refused it)

    asTemplate: the staff chose to write first. Outside the 24 h window (or to a
    client who never wrote) the text goes inside the mensaje_negocio template,
    from the number the client used before, else the business sender number.
    Inside the window it is sent as plain text, as always."""
    row = (json_file.get("whatsappStaffReply") or [{}])[0]
    try:
        company_id = int(row.get("companyId"))
        user_id = int(row.get("userId"))
    except (TypeError, ValueError):
        return JSONResponse({"error": "companyId and userId are required"}, status_code=400)
    phone10 = re.sub(r"\D", "", str(row.get("phone10") or ""))[-10:]
    body = (row.get("body") or "").strip()
    as_template = bool(row.get("asTemplate"))
    if len(phone10) != 10 or not body:
        return JSONResponse({"error": "phone10 (10 digits) and body are required"}, status_code=400)
    if len(body) > STAFF_REPLY_MAX_CHARS:
        return JSONResponse({"error": f"body is longer than {STAFF_REPLY_MAX_CHARS} characters"}, status_code=400)

    try:
        found = assistant_sp("sp_whatsappAgentConversations", {"whatsappAgentConversations": [
            {"action": "channel", "companyId": company_id, "phone10": phone10}]})
    except Exception as e:
        logger.exception("[whatsappCloud] staff reply: channel lookup failed")
        return JSONResponse({"error": str(e)}, status_code=500)
    if found.get("error"):
        return JSONResponse({"error": found["error"]}, status_code=500)
    target = (found.get("result") or [None])[0]
    channel = whatsappChannels.get_channel(target["phoneNumberId"]) if target else None
    if channel and channel.get("companyId") != company_id:
        logger.info("[staffReply] picked number belongs to company %s, not %s", channel.get("companyId"), company_id)
        channel = None

    last_in = target.get("lastInboundUtc") if channel else None
    window_open = bool(last_in) and (datetime.now(timezone.utc)
                                     - datetime.fromisoformat(last_in).replace(tzinfo=timezone.utc) <= _SERVICE_WINDOW)
    logger.info("[staffReply] lookup | company=%s phone=…%s channel=%s number=…%s lastInboundUtc=%s window=%s asTemplate=%s",
                company_id, phone10[-4:], (channel or {}).get("channelId"),
                str((channel or {}).get("phoneNumberId") or "")[-4:], last_in, window_open, as_template)
    if not window_open:
        if as_template:
            return _staff_template(company_id, user_id, channel, target, phone10, body)
        if not channel:
            return JSONResponse({"error": "no_channel"}, status_code=404)
        return JSONResponse({"error": "outside_24h", "lastInboundUtc": last_in}, status_code=409)

    customer = target["customerPhone"]
    sent, channel, attempts = _send_from_company_numbers(company_id, channel, customer, body)
    if sent is None:
        return JSONResponse({"error": "send_failed", "attempts": attempts}, status_code=502)

    try:
        _record_outbound(channel=channel, phone_number=customer, message_body=body,
                         response_body=f"userId={user_id}", status="staff_sent",
                         wamid=sent.get("messageId"), sender_kind="staff_pos")
    except Exception:
        logger.exception("[whatsappCloud] failed to log staff reply")
    # No message text or phone here: the logs stay free of PII.
    log_workflow_step("staff_reply", workflow_name="whatsapp_chat", entity="whatsappChannel",
                      entity_id=channel["channelId"], message=f"userId={user_id} company={company_id}")
    return JSONResponse({"sent": True, "messageId": sent.get("messageId"), "viaTemplate": False, "attempts": attempts,
                         "atUtc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")}, status_code=200)


def _masked(text: Any, limit: int = 240) -> str:
    """Error text safe for logs and for the app: long digit runs (phones, ids) keep their last 4."""
    return re.sub(r"\d{8,}", lambda m: "…" + m.group()[-4:], str(text))[:limit]


def _send_from_company_numbers(company_id: int, first: dict, customer: str, body: str):
    """Sends from `first` (the number the lookup picked); if Meta refuses it, tries
    the company's other active numbers. The lookup can pick a number the customer
    isn't writing to (its conversation row was stale), and Meta answers 400 from
    that one. Returns (sent, channel, attempts); sent is None when every number
    failed. attempts = [{channelId, number (last 4), result}] for the app's console."""
    attempts: list = []

    def attempt(channel: dict):
        number = str(channel.get("phoneNumberId") or "")[-4:]
        try:
            sent = send_text(channel, customer, body)
            attempts.append({"channelId": channel.get("channelId"), "number": number, "result": "sent"})
            logger.info("[staffReply] sent | channel=%s number=…%s", channel.get("channelId"), number)
            return sent
        except Exception as e:
            reason = _masked(e)
            attempts.append({"channelId": channel.get("channelId"), "number": number, "result": reason})
            logger.warning("[staffReply] refused | channel=%s number=…%s reason=%s", channel.get("channelId"), number, reason)
            log_workflow_step("staff_reply", workflow_name="whatsapp_chat", status="FAILED", entity="whatsappChannel",
                              entity_id=channel.get("channelId"), message=reason)
            return None

    sent = attempt(first)
    if sent is not None:
        return sent, first, attempts
    try:
        others = [c for c in whatsappChannels.company_channels(company_id)
                  if c.get("phoneNumberId") != first.get("phoneNumberId")]
    except Exception:
        logger.exception("[whatsappCloud] staff reply: listing the company's numbers failed")
        others = []
    logger.info("[staffReply] trying the company's other numbers | count=%s", len(others))
    for channel in others:
        sent = attempt(channel)
        if sent is not None:
            return sent, channel, attempts
    return None, first, attempts


def _staff_template(company_id: int, user_id: int, channel: dict | None, target: dict | None,
                    phone10: str, body: str) -> JSONResponse:
    """Staff write first: mensaje_negocio from the client's usual number, else the
    business sender. Meta answers 132001 until the template is approved."""
    if len(body) > STAFF_TEMPLATE_MAX_CHARS:
        return JSONResponse({"error": "too_long_for_template", "max": STAFF_TEMPLATE_MAX_CHARS}, status_code=400)
    sender = channel or outbound_channel()
    if not sender:
        return JSONResponse({"error": "no_channel"}, status_code=404)
    customer = (target or {}).get("customerPhone") or f"+52{phone10}"
    logger.info("[staffReply] template | company=%s phone=…%s channel=%s number=…%s", company_id, phone10[-4:],
                sender.get("channelId"), str(sender.get("phoneNumberId") or "")[-4:])
    from modules.companies import company_name  # lazy: keeps this module's imports light
    try:
        sent = send_template(sender, customer, STAFF_TEMPLATE, [company_name({"companyId": company_id}) or "tu negocio",
                                                                body])
    except Exception as e:
        reason = _masked(e)
        logger.warning("[staffReply] template refused | channel=%s reason=%s", sender.get("channelId"), reason)
        log_workflow_step("staff_template", workflow_name="whatsapp_chat", status="FAILED",
                          entity="whatsappChannel", entity_id=sender.get("channelId"), message=reason)
        return JSONResponse({"error": "template_failed", "reason": reason}, status_code=502)
    try:
        _record_outbound(channel=sender, phone_number=customer, message_body=body,
                         response_body=f"userId={user_id} template={STAFF_TEMPLATE}", status="staff_sent",
                         wamid=(sent or {}).get("messageId"), sender_kind="staff_template")
    except Exception:
        logger.exception("[whatsappCloud] failed to log staff template")
    log_workflow_step("staff_template", workflow_name="whatsapp_chat", entity="whatsappChannel",
                      entity_id=sender.get("channelId"), message=f"userId={user_id} company={company_id}")
    return JSONResponse({"sent": True, "messageId": sent.get("messageId"), "viaTemplate": True,
                         "atUtc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")}, status_code=200)
