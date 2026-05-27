import os
import re
from typing import Optional, Dict, Any

from twilio.rest import Client


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


def send_ticket_sms(ticket_id: str, phone: str, message: Optional[str] = None, receipt_url: Optional[str] = None) -> Dict[str, Any]:
    _validate_phone_e164(phone)

    from_phone = os.getenv("TWILIO_SMS_FROM")
    if not from_phone:
        raise ValueError("Missing TWILIO_SMS_FROM environment variable.")

    body = _build_message(ticket_id, message, receipt_url)
    client = _twilio_client()

    msg = client.messages.create(
        body=body,
        from_=from_phone,
        to=phone
    )

    return {
        "channel": "sms",
        "ticketId": ticket_id,
        "to": phone,
        "provider": "twilio",
        "messageSid": msg.sid,
        "status": msg.status
    }


def send_ticket_whatsapp(ticket_id: str, phone: str, message: Optional[str] = None, receipt_url: Optional[str] = None) -> Dict[str, Any]:
    _validate_phone_e164(phone)

    wa_from = os.getenv("TWILIO_WHATSAPP_FROM")
    if not wa_from:
        raise ValueError("Missing TWILIO_WHATSAPP_FROM environment variable. Expected value like: whatsapp:+14155238886")

    body = _build_message(ticket_id, message, receipt_url)
    client = _twilio_client()

    to_wa = f"whatsapp:{phone}"
    from_wa = wa_from if wa_from.startswith("whatsapp:") else f"whatsapp:{wa_from}"

    msg = client.messages.create(
        body=body,
        from_=from_wa,
        to=to_wa
    )

    return {
        "channel": "whatsapp",
        "ticketId": ticket_id,
        "to": phone,
        "provider": "twilio",
        "messageSid": msg.sid,
        "status": msg.status
    }
