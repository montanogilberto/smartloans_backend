"""
WhatsApp reservations bot — customers book any service from the company's
catalog (sp_reservationServices) by chatting with its WhatsApp number
(Cloud API, see modules/whatsappCloud.py).

Same propose → confirm → execute split as modules/posSupportChat.py:
- The LLM agent (LoanAgents_SmartLoans /support/whatsapp-reservations) only
  talks, checks availability and PROPOSES a CREATE_RESERVATION.
- The customer's "sí" is detected here deterministically (never by the LLM),
  and only this module creates the reservation — through the same
  create_reservation() the kiosk uses, so the slot capacity check is shared.
- companyId (WA_COMPANY_ID) and phone (the WhatsApp sender) are always set
  here, never taken from the agent's fields.

Coexistence: the number is also used from the WhatsApp Business app. When
staff answer a chat from the app, Meta sends an smb_message_echoes webhook;
the bot then stays quiet in that chat for STAFF_PAUSE_SECONDS so the
customer doesn't get answers from both.

State (pending proposals, staff pauses) is in-process only — same tradeoff
posSupportChat accepts: a restart just means the customer re-confirms.

Env vars:
  WA_COMPANY_ID           companyId the WhatsApp number belongs to; unset = bot off
  COMPANY_NAME            business name the agent introduces (shared with reservations.py)
  NEGOTIATION_AGENT_URL   LoanAgents_SmartLoans base URL (shared with posSupportChat)
"""

import asyncio
import logging
import os
import time

import httpx

from modules.posSupportChat import _classify_confirmation
from modules.reservations import COMPANY_NAME, available_slots, create_reservation, notify_pos
from observability.integrations import timed_integration

logger = logging.getLogger(__name__)

AGENT_URL = os.environ.get("NEGOTIATION_AGENT_URL", "").rstrip("/")
PENDING_TTL_SECONDS = 600
STAFF_PAUSE_SECONDS = 2 * 60 * 60

# phone (E.164) -> {"fields": dict, "expiresAt": float}
_PENDING: dict[str, dict] = {}
# phone (E.164) -> unix time until which the bot stays quiet
_STAFF_PAUSED_UNTIL: dict[str, float] = {}
# phone (E.164) -> last reservation booked in this chat, passed to the agent
# so it knows the booking went through (it never sees the "sí" turn).
_LAST_BOOKED: dict[str, dict] = {}

_FALLBACK_REPLY = ("Por el momento no puedo procesar tu mensaje. "
                   "Alguien del equipo te responderá en breve.")


def _company_id() -> int | None:
    value = os.environ.get("WA_COMPANY_ID", "")
    return int(value) if value.isdigit() else None


def pause_for_staff(phone: str) -> None:
    _STAFF_PAUSED_UNTIL[phone] = time.time() + STAFF_PAUSE_SECONDS
    _PENDING.pop(phone, None)


def _book(company_id: int, phone: str, profile_name: str | None, fields: dict) -> str:
    """Executes a confirmed proposal. Re-checks action 6 first: that is where
    business hours live, and the slot may have filled since the proposal."""
    date = fields.get("reservationDate")
    slot = fields.get("timeSlot")
    service_id = fields.get("reservationServiceId")

    availability = available_slots(company_id, date, service_id)
    free = {s.get("timeSlot") for s in availability.get("slots") or []}
    if slot not in free:
        return (f"Lo siento, el horario del {date} a las {slot} ya no está disponible. "
                f"¿Quieres que te muestre otros horarios?")

    row = create_reservation({
        "clientName": fields.get("clientName") or profile_name or "Cliente WhatsApp",
        "reservationServiceId": service_id,
        "serviceDetail": fields.get("serviceDetail"),
        "reservationDate": date,
        "timeSlot": slot,
        "notes": fields.get("notes"),
        # Trusted values last so they always win.
        "companyId": company_id,
        "phone": phone,
    })
    if row.get("error"):
        logger.warning("[whatsappReservations] create failed | phone=%s error=%s", phone, row)
        return row.get("message") or "No pude registrar la reservación. Intenta con otro horario."

    _LAST_BOOKED[phone] = row
    asyncio.run(notify_pos(row, source="WhatsApp"))
    return (f"✅ Listo, tu reservación quedó registrada.\n"
            f"{row.get('serviceType')} — {row.get('reservationDate')} a las {row.get('timeSlot')}\n"
            f"Folio: #{row['reservationId']}\n"
            f"Te esperamos. Si necesitas cambiarla, escríbenos aquí.")


def _ask_agent(company_id: int, phone: str, profile_name: str | None, text: str) -> tuple[str, dict | None]:
    request_body = {
        "companyId": company_id,
        "companyName": COMPANY_NAME,
        "phone": phone,
        "customerName": profile_name,
        "message": text,
        "recentReservation": _LAST_BOOKED.get(phone),
    }
    with timed_integration("loanagents_smartloans", "whatsapp_reservations", request=request_body) as span:
        resp = httpx.post(f"{AGENT_URL}/support/whatsapp-reservations", json=request_body, timeout=30.0)
        span.http_status = resp.status_code
        resp.raise_for_status()
        data = resp.json()
        span.response = data
        return data["reply"], data.get("pendingAction")


def reply_to(phone: str, profile_name: str | None, text: str) -> str | None:
    """Returns the text to send back, or None to stay silent."""
    company_id = _company_id()
    if company_id is None or not AGENT_URL:
        return None
    if _STAFF_PAUSED_UNTIL.get(phone, 0) > time.time():
        logger.info("[whatsappReservations] staff is handling %s — bot silent", phone)
        return None

    pending = _PENDING.get(phone)
    if pending and pending["expiresAt"] < time.time():
        _PENDING.pop(phone, None)
        pending = None

    if pending:
        decision = _classify_confirmation(text)
        if decision == "confirm":
            _PENDING.pop(phone, None)
            return _book(company_id, phone, profile_name, pending["fields"])
        if decision == "cancel":
            _PENDING.pop(phone, None)
            return "Cancelado, no se hizo la reservación. ¿Te ayudo con otro horario?"
        # Anything else: the customer changed something — let the agent
        # re-propose; the old proposal is dropped.
        _PENDING.pop(phone, None)

    try:
        reply, pending_action = _ask_agent(company_id, phone, profile_name, text)
    except Exception:
        logger.exception("[whatsappReservations] agent call failed | phone=%s", phone)
        return _FALLBACK_REPLY

    if pending_action and pending_action.get("capability") == "CREATE_RESERVATION":
        _PENDING[phone] = {"fields": pending_action.get("fields") or {},
                           "expiresAt": time.time() + PENDING_TTL_SECONDS}
    return reply
