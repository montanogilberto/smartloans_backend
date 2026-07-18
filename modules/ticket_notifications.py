import os
import re
import logging
from typing import Optional, Dict, Any

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


def send_whatsapp(phone: str, body: str) -> Dict[str, Any]:
    """Send a plain WhatsApp message via Twilio. Requires TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_WHATSAPP_FROM."""
    _validate_phone_e164(phone)

    wa_from = os.getenv("TWILIO_WHATSAPP_FROM")
    if not wa_from:
        raise ValueError("Missing TWILIO_WHATSAPP_FROM environment variable. Expected value like: whatsapp:+14155238886")

    client = _twilio_client()
    to_wa = f"whatsapp:{phone}"
    from_wa = wa_from if wa_from.startswith("whatsapp:") else f"whatsapp:{wa_from}"
    status_callback_url = os.getenv("TWILIO_WHATSAPP_STATUS_CALLBACK_URL")

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
    result = send_whatsapp(phone, body)
    result["ticketId"] = ticket_id
    return result
