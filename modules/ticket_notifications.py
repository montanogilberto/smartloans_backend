import os
import re
import logging
from typing import Any, Dict, List, Optional

from twilio.rest import Client


logger = logging.getLogger(__name__)

E164_REGEX = re.compile(r"^\+[1-9]\d{1,14}$")


def _validate_phone_e164(phone: str) -> None:
    if not phone or not E164_REGEX.match(phone):
        raise ValueError("Invalid phone format. Use E.164 format, e.g. +521234567890")


def _build_message(ticket_id: str, message: Optional[str], receipt_url: Optional[str]) -> str:
    base_message = message.strip() if message else f"Ticket #{ticket_id} update."
    if receipt_url:
        return f"{base_message}\nReceipt: {receipt_url}"
    return base_message


def _twilio_client() -> Client:
    account_sid = os.getenv("TWILIO_ACCOUNT_SID")
    auth_token = os.getenv("TWILIO_AUTH_TOKEN")

    if not account_sid or not auth_token:
        raise ValueError("Missing Twilio credentials: TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN are required.")

    return Client(account_sid, auth_token)


def send_sms(phone: str, body: str) -> Dict[str, Any]:
    """Send a plain SMS via Twilio. Requires TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_SMS_FROM."""
    _validate_phone_e164(phone)

    from_phone = os.getenv("TWILIO_SMS_FROM")
    if not from_phone:
        raise ValueError("Missing TWILIO_SMS_FROM environment variable.")

    client = _twilio_client()
    status_callback_url = os.getenv("TWILIO_SMS_STATUS_CALLBACK_URL")

    message_kwargs = {
        "body": body,
        "from_": from_phone,
        "to": phone
    }
    if status_callback_url:
        message_kwargs["status_callback"] = status_callback_url

    logger.info("[send_sms] sending | to=%s callback_configured=%s", phone, bool(status_callback_url))
    msg = client.messages.create(**message_kwargs)
    logger.info("[send_sms] sent | sid=%s status=%s", msg.sid, msg.status)

    return {
        "channel": "sms",
        "to": phone,
        "provider": "twilio",
        "messageSid": msg.sid,
        "status": msg.status
    }


def send_whatsapp(phone: str, body: str, template: Optional[str] = None,
                  params: Optional[List[Any]] = None,
                  button_param: Optional[str] = None) -> Dict[str, Any]:
    """Send a WhatsApp message through Meta's Cloud API as an approved
    `template` (needs WA_SENDER_PHONE_NUMBER_ID).

    Twilio is no longer used for WhatsApp (2026-10-16): the fallback below is
    commented out. When there is no template, Meta isn't configured, or Meta
    rejects the template, this raises — every caller already handles that
    (notificationDispatch moves on to SMS, reminders fall back to SMS, the
    rest log it). `body` is only used by the commented-out Twilio path."""
    _validate_phone_e164(phone)

    if not template:
        raise RuntimeError("WhatsApp requires a Meta template (Twilio disabled): NO_TEMPLATE")

    # Lazy: whatsappCloud → whatsappReservations → reservations → this module.
    from modules import whatsappCloud
    channel = whatsappCloud.outbound_channel()
    if not channel:
        raise RuntimeError("WhatsApp via Meta not configured (Twilio disabled): "
                           "META_NOT_CONFIGURED (WA_SENDER_PHONE_NUMBER_ID)")
    try:
        return whatsappCloud.send_template(channel, phone, template, params or [], button_param)
    except Exception as e:
        raise RuntimeError(f"Meta template {template} failed (Twilio disabled): {e}") from e

    # ── Twilio fallback — DISABLED 2026-10-16 (WhatsApp goes only through Meta) ──
    # Free-form `body` via Twilio; only landed inside the 24h window (63016
    # outside it). To re-enable, restore this block in place of the raises above.
    #
    # meta_error = None
    # if template:
    #     from modules import whatsappCloud
    #     channel = whatsappCloud.outbound_channel()
    #     if channel:
    #         try:
    #             return whatsappCloud.send_template(channel, phone, template, params or [], button_param)
    #         except Exception as e:
    #             meta_error = e
    #             logger.warning("[send_whatsapp] Meta template %s failed, falling back to Twilio: %s", template, e)
    #
    # try:
    #     result = _send_whatsapp_twilio(phone, body)
    #     if meta_error is not None:
    #         result["metaFallbackReason"] = f"META_REJECTED: {str(meta_error)[:200]}"
    #     elif not template:
    #         result["metaFallbackReason"] = "NO_TEMPLATE"
    #     else:
    #         result["metaFallbackReason"] = "META_NOT_CONFIGURED (WA_SENDER_PHONE_NUMBER_ID)"
    #     return result
    # except Exception as e:
    #     if meta_error:
    #         raise RuntimeError(f"Meta: {meta_error} | Twilio: {e}") from e
    #     raise


def whatsapp_status_callback_url() -> str:
    """Where Twilio reports delivery (delivered/read/failed) for WhatsApp.
    TWILIO_WHATSAPP_STATUS_CALLBACK_URL wins; otherwise this backend's own
    /whatsapp/status — without a callback URL Twilio never reports back and a
    rejected message stays "sent" forever (every WhatsApp in Sep–Oct 2026
    failed with 63005 while the dispatch log said "sent")."""
    explicit = (os.getenv("TWILIO_WHATSAPP_STATUS_CALLBACK_URL") or "").strip()
    if explicit:
        return explicit
    base = os.getenv("BACKEND_PUBLIC_URL", "https://smartloansbackend.azurewebsites.net").rstrip("/")
    return f"{base}/whatsapp/status"


def _send_whatsapp_twilio(phone: str, body: str) -> Dict[str, Any]:
    """UNUSED since 2026-10-16 — Twilio WhatsApp disabled, see send_whatsapp.
    Plain WhatsApp message via Twilio. Requires TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_WHATSAPP_FROM."""

    wa_from = os.getenv("TWILIO_WHATSAPP_FROM")
    if not wa_from:
        raise ValueError("Missing TWILIO_WHATSAPP_FROM environment variable. Expected value like: whatsapp:+14155238886")

    client = _twilio_client()
    to_wa = f"whatsapp:{phone}"
    from_wa = wa_from if wa_from.startswith("whatsapp:") else f"whatsapp:{wa_from}"
    status_callback_url = whatsapp_status_callback_url()

    message_kwargs = {
        "body": body,
        "from_": from_wa,
        "to": to_wa
    }
    if status_callback_url:
        message_kwargs["status_callback"] = status_callback_url

    logger.info("[send_whatsapp] sending | to=%s callback_configured=%s", to_wa, bool(status_callback_url))
    msg = client.messages.create(**message_kwargs)
    logger.info("[send_whatsapp] sent | sid=%s status=%s", msg.sid, msg.status)

    return {
        "channel": "whatsapp",
        "to": phone,
        "provider": "twilio",
        "messageSid": msg.sid,
        "status": msg.status
    }


def send_ticket_sms(ticket_id: str, phone: str, message: Optional[str] = None, receipt_url: Optional[str] = None) -> Dict[str, Any]:
    logger.info("[send_ticket_sms] start | ticket_id=%s to=%s", ticket_id, phone)
    body = _build_message(ticket_id, message, receipt_url)
    result = send_sms(phone, body)
    result["ticketId"] = ticket_id
    return result


def send_ticket_whatsapp(ticket_id: str, phone: str, message: Optional[str] = None, receipt_url: Optional[str] = None) -> Dict[str, Any]:
    logger.info("[send_ticket_whatsapp] start | ticket_id=%s to=%s", ticket_id, phone)
    body = _build_message(ticket_id, message, receipt_url)
    detail = message.strip() if message else f"Ticket #{ticket_id}"
    if receipt_url:
        result = send_whatsapp(phone, body, "comprobante_listo", [detail, receipt_url])
    else:
        result = send_whatsapp(phone, body, "detalle_compra", [detail])
    result["ticketId"] = ticket_id
    return result
