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

Handoff: when the customer asks for a person (or the agent can't help), the
agent proposes REQUEST_HUMAN. That needs no "sí": the bot goes quiet in the
chat for STAFF_PAUSE_SECONDS and the branch's POS users get a push, so staff
answer from the WhatsApp Business app.

Env vars:
  NEGOTIATION_AGENT_URL   LoanAgents_SmartLoans base URL (shared with posSupportChat)
"""

import asyncio
import json
import logging
import os
import re

import time

import httpx

from databases import connection
from modules import whatsappChannels
from modules.whatsappAssistant import _sp as assistant_sp
from modules.posSupportChat import _classify_confirmation
from modules.pushNotifications import pushNotifications_sp, resolve_push_user_ids
from modules.reservations import available_slots, create_reservation, notify_pos
from observability.integrations import timed_integration

logger = logging.getLogger(__name__)

AGENT_URL = os.environ.get("NEGOTIATION_AGENT_URL", "").rstrip("/")
PENDING_TTL_SECONDS = 600
STAFF_PAUSE_SECONDS = 2 * 60 * 60

# Sent when the agent service fails. It must not promise a person: nobody is
# notified on this path.
_FALLBACK_REPLY = ("Perdón, tuve un problema para responderte. "
                   "¿Me lo puedes escribir de nuevo en un momento?")


def pause_for_staff(channel: dict, phone: str) -> None:
    whatsappChannels.pause_for_staff(channel["channelId"], phone, STAFF_PAUSE_SECONDS)


def _hand_off_to_staff(channel: dict, phone: str, profile_name: str | None,
                      reason: str | None) -> None:
    """Bot steps aside in this chat and the company's POS users get a push."""
    whatsappChannels.pause_for_staff(channel["channelId"], phone, STAFF_PAUSE_SECONDS)
    who = profile_name or phone
    branch = f" ({channel['branchName']})" if channel.get("branchName") else ""
    try:
        asyncio.run(pushNotifications_sp({"pushNotifications": [{
            "action": 1,
            "companyId": channel["companyId"],
            "title": f"💬 Cliente pide atención por WhatsApp{branch}",
            "message": f"{who} ({phone}): {reason or 'quiere hablar con alguien'}. Responde desde WhatsApp Business.",
            "notificationType": "Info",
            "priority": "High",
            "targetType": "Company",
            "targetCompanyId": channel["companyId"],
            "payloadJson": json.dumps({"type": "WhatsAppHandoff", "phone": phone,
                                       "channelId": channel["channelId"]}),
        }]}))
    except Exception:
        logger.exception("[whatsappReservations] handoff push failed | phone=%s", phone)
    logger.info("[whatsappReservations] handed off to staff | channel=%s phone=%s reason=%s",
                channel["channelId"], phone, reason)


# Push copies of WhatsApp events. They never change what the customer gets
# on WhatsApp: every failure here is logged and swallowed.
FAILURE_ALERT_EVERY_SECONDS = 15 * 60
_last_failure_alert: dict = {}


def _customer_user_id(company_id: int, phone: str) -> int | None:
    """The app user behind this WhatsApp number (same phone → client match
    as the points lookup), or None when they don't have the app — then no
    push is created at all."""
    result = assistant_sp("sp_whatsappCustomerRewards",
                          {"customerRewards": [{"companyId": company_id, "phone": phone}]})
    row = (result.get("result") or [{}])[0]
    client_id = row.get("clientId") if row.get("status") == "found" else None
    if not client_id:
        return None
    conn = connection()
    try:
        return resolve_push_user_ids(conn.cursor(), [client_id]).get(client_id)
    finally:
        conn.close()


def _push_booking_to_customer(channel: dict, phone: str, row: dict) -> None:
    try:
        user_id = _customer_user_id(channel["companyId"], phone)
        if not user_id:
            return
        branch = f" · {channel['branchName']}" if channel.get("branchName") else ""
        asyncio.run(pushNotifications_sp({"pushNotifications": [{
            "action": 1,
            "companyId": channel["companyId"],
            "title": f"✅ Reservación confirmada #{row['reservationId']}",
            "message": f"{row.get('serviceType')} — {row.get('reservationDate')} a las {row.get('timeSlot')}{branch}",
            "notificationType": "Info",
            "priority": "High",
            "targetType": "User",
            "targetUserId": user_id,
            "payloadJson": json.dumps({"type": "ReservationConfirmed", "reservationId": row["reservationId"]}),
        }]}))
    except Exception:
        logger.exception("[whatsappReservations] customer push failed | phone=%s", phone)


def _push_agent_failure_to_staff(channel: dict, phone: str, profile_name: str | None, text: str) -> None:
    """At most one alert per channel every 15 min, so an outage doesn't
    flood the POS with one push per customer message."""
    now = time.time()
    if now - _last_failure_alert.get(channel["channelId"], 0) < FAILURE_ALERT_EVERY_SECONDS:
        return
    _last_failure_alert[channel["channelId"]] = now
    branch = f" ({channel['branchName']})" if channel.get("branchName") else ""
    try:
        asyncio.run(pushNotifications_sp({"pushNotifications": [{
            "action": 1,
            "companyId": channel["companyId"],
            "title": f"⚠️ El asistente de WhatsApp no pudo responder{branch}",
            "message": f"{profile_name or phone} ({phone}): \"{(text or '')[:120]}\". Revisa el chat en WhatsApp Business.",
            "notificationType": "Info",
            "priority": "High",
            "targetType": "Company",
            "targetCompanyId": channel["companyId"],
            "payloadJson": json.dumps({"type": "WhatsAppAgentFailed", "phone": phone}),
        }]}))
    except Exception:
        logger.exception("[whatsappReservations] staff failure push failed | phone=%s", phone)


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
        "source": "whatsapp",
    })
    if row.get("error"):
        logger.warning("[whatsappReservations] create failed | phone=%s error=%s", phone, row)
        return row.get("message") or "No pude registrar la reservación. Intenta con otro horario."

    whatsappChannels.set_last_booked(channel["channelId"], phone, row)
    asyncio.run(notify_pos(row, source="WhatsApp"))
    _push_booking_to_customer(channel, phone, row)
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
    with timed_integration("loanagents_smartloans", "whatsapp_reservations", request=request_body,
                           company_id=channel["companyId"]) as span:
        resp = httpx.post(f"{AGENT_URL}/support/whatsapp-reservations", json=request_body, timeout=30.0)
        span.http_status = resp.status_code
        resp.raise_for_status()
        data = resp.json()
        span.response = data
        return data["reply"], data.get("pendingAction")


_CHANGE_WORDS = {"pero", "mejor", "cambia", "cambiar", "otro", "otra", "hoy", "mañana",
                 "lunes", "martes", "miércoles", "miercoles", "jueves", "viernes",
                 "sábado", "sabado", "domingo", "tarde", "temprano"}


def _changes_booking(text: str) -> bool:
    """A yes/no that also carries new details (a time, a day, "pero ...")
    is a changed request, not a plain answer to the proposal."""
    words = re.sub(r"[^\w\s]", " ", (text or "").lower()).split()
    return (bool(re.search(r"\d", text or "")) or bool(_CHANGE_WORDS & set(words))
            or len(words) > 5)


def reply_to(channel: dict, phone: str, profile_name: str | None, text: str,
             on_answering=None) -> str | None:
    """Returns the text to send back, or None to stay silent. on_answering()
    runs once the bot knows it will answer (whatsappCloud shows "escribiendo…")."""
    if not AGENT_URL:
        return None
    channel_id = channel["channelId"]
    state = whatsappChannels.get_state(channel_id, phone)
    if state["staffPaused"]:
        logger.info("[whatsappReservations] staff is handling %s on channel %s — bot silent",
                    phone, channel_id)
        return None
    if on_answering:
        on_answering()

    pending = state["pending"]  # already None when expired (checked by the SP)
    if pending:
        decision = _classify_confirmation(text)
        if decision and _changes_booking(text):
            # "sí, pero a las 5" must not book the OLD time: the agent gets it
            # and re-proposes with the change.
            decision = None
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
        _push_agent_failure_to_staff(channel, phone, profile_name, text)
        return _FALLBACK_REPLY

    capability = (pending_action or {}).get("capability")
    if capability == "REQUEST_HUMAN":
        # No confirmation step: asking for a person is not a write the
        # customer could regret, and waiting for "sí" would just delay them.
        _hand_off_to_staff(channel, phone, profile_name,
                           (pending_action.get("fields") or {}).get("reason"))
    elif capability == "CREATE_RESERVATION":
        whatsappChannels.set_pending(channel_id, phone, pending_action.get("fields") or {},
                                     PENDING_TTL_SECONDS)
    return reply
