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
- companyId / branchId come from the channel the customer wrote to (one
  WhatsApp number per branch, dbo.whatsappChannels) and phone from the
  WhatsApp sender — always set here, never taken from the agent's fields.

Coexistence: the number is also used from the WhatsApp Business app. When
staff answer a chat from the app, Meta sends an smb_message_echoes webhook;
the bot then stays quiet in that chat for STAFF_PAUSE_SECONDS so the
customer doesn't get answers from both.

State (pending proposal, staff pause, last booking) lives in
dbo.whatsappConversations per (channel, customer), so it is shared by every
App Service instance and survives restarts.

Env vars:
  NEGOTIATION_AGENT_URL   LoanAgents_SmartLoans base URL (shared with posSupportChat)
"""

import asyncio
import logging
import os

import httpx

from modules import whatsappChannels
from modules.posSupportChat import _classify_confirmation
from modules.reservations import available_slots, create_reservation, notify_pos
from observability.integrations import timed_integration

logger = logging.getLogger(__name__)

AGENT_URL = os.environ.get("NEGOTIATION_AGENT_URL", "").rstrip("/")
PENDING_TTL_SECONDS = 600
STAFF_PAUSE_SECONDS = 2 * 60 * 60

_FALLBACK_REPLY = ("Por el momento no puedo procesar tu mensaje. "
                   "Alguien del equipo te responderá en breve.")


def pause_for_staff(channel: dict, phone: str) -> None:
    whatsappChannels.pause_for_staff(channel["channelId"], phone, STAFF_PAUSE_SECONDS)


def _book(channel: dict, phone: str, profile_name: str | None, fields: dict) -> str:
    """Executes a confirmed proposal. Re-checks action 6 first: that is where
    business hours live, and the slot may have filled since the proposal."""
    date = fields.get("reservationDate")
    slot = fields.get("timeSlot")
    service_id = fields.get("reservationServiceId")
    company_id = channel["companyId"]

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
        "branchId": channel.get("branchId"),
        "phone": phone,
    })
    if row.get("error"):
        logger.warning("[whatsappReservations] create failed | phone=%s error=%s", phone, row)
        return row.get("message") or "No pude registrar la reservación. Intenta con otro horario."

    whatsappChannels.set_last_booked(channel["channelId"], phone, row)
    asyncio.run(notify_pos(row, source="WhatsApp"))
    return (f"✅ Listo, tu reservación quedó registrada.\n"
            f"{row.get('serviceType')} — {row.get('reservationDate')} a las {row.get('timeSlot')}\n"
            f"Folio: #{row['reservationId']}\n"
            f"Te esperamos. Si necesitas cambiarla, escríbenos aquí.")


def _ask_agent(channel: dict, phone: str, profile_name: str | None, text: str,
               last_booked: dict | None) -> tuple[str, dict | None]:
    request_body = {
        "companyId": channel["companyId"],
        "companyName": channel.get("companyName"),
        "branchId": channel.get("branchId"),
        "branchName": channel.get("branchName"),
        "phone": phone,
        "customerName": profile_name,
        "message": text,
        "recentReservation": last_booked,
    }
    with timed_integration("loanagents_smartloans", "whatsapp_reservations", request=request_body) as span:
        resp = httpx.post(f"{AGENT_URL}/support/whatsapp-reservations", json=request_body, timeout=30.0)
        span.http_status = resp.status_code
        resp.raise_for_status()
        data = resp.json()
        span.response = data
        return data["reply"], data.get("pendingAction")


def reply_to(channel: dict, phone: str, profile_name: str | None, text: str) -> str | None:
    """Returns the text to send back, or None to stay silent."""
    if not AGENT_URL:
        return None
    channel_id = channel["channelId"]
    state = whatsappChannels.get_state(channel_id, phone)
    if state["staffPaused"]:
        logger.info("[whatsappReservations] staff is handling %s on channel %s — bot silent",
                    phone, channel_id)
        return None

    pending = state["pending"]  # already None when expired (checked by the SP)
    if pending:
        decision = _classify_confirmation(text)
        # Any reply ends the proposal: confirmed, cancelled, or the customer
        # changed something and the agent re-proposes below.
        whatsappChannels.clear_pending(channel_id, phone)
        if decision == "confirm":
            return _book(channel, phone, profile_name, pending)
        if decision == "cancel":
            return "Cancelado, no se hizo la reservación. ¿Te ayudo con otro horario?"

    try:
        reply, pending_action = _ask_agent(channel, phone, profile_name, text, state["lastBooked"])
    except Exception:
        logger.exception("[whatsappReservations] agent call failed | phone=%s", phone)
        return _FALLBACK_REPLY

    if pending_action and pending_action.get("capability") == "CREATE_RESERVATION":
        whatsappChannels.set_pending(channel_id, phone, pending_action.get("fields") or {},
                                     PENDING_TTL_SECONDS)
    return reply
