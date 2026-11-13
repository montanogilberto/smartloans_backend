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

Always on: the agent answers EVERY customer message — support is automatic.
Staff can also write (from the POS or the WhatsApp Business app); that never
silences the agent (decided 2026-11-02 — a staff "hola" used to pause it for
2 h and the customer was left without answers). Pauses already stored in
whatsappConversations.staffPausedUntil are ignored.

State (pending proposal, last booking) lives in
dbo.whatsappConversations per (channel, customer), so it is shared by every
App Service instance and survives restarts.

Handoff: when the customer asks for a person (or the agent can't help), the
agent proposes REQUEST_HUMAN. That needs no "sí": the branch's POS users get
a push so someone from the team follows up, and the agent keeps answering.

Registration: "quiero registrarme" goes to the agent's registration sub-agent,
which asks only the full name and proposes REGISTER_CLIENT. On "sí" this
module re-checks the sender's phone isn't a client yet and creates it through
sp_clients (clientType 'pos') with the channel's companyId and the sender's
phone — the agent never supplies either.

Client QR: "mi QR" (menu option 7) makes the agent propose SEND_CLIENT_QR,
also without "sí". This module finds the sender's client by phone (the same
match as their points) and sends the QR image the POS scanner reads.

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
from modules.clients import clients_sp
from modules.whatsappAssistant import _sp as assistant_sp
from modules.posSupportChat import _classify_confirmation
from modules.pushNotifications import pushNotifications_sp, resolve_push_user_ids
from modules.reservations import available_slots, create_reservation, notify_pos
from observability.integrations import timed_integration

logger = logging.getLogger(__name__)

AGENT_URL = os.environ.get("NEGOTIATION_AGENT_URL", "").rstrip("/")
PENDING_TTL_SECONDS = 600

# Sent when the agent service fails. It must not promise a person: nobody is
# notified on this path.
_FALLBACK_REPLY = ("Perdón, tuve un problema para responderte. "
                   "¿Me lo puedes escribir de nuevo en un momento?")


def _hand_off_to_staff(channel: dict, phone: str, profile_name: str | None,
                      reason: str | None) -> None:
    """The company's POS users get a push; the agent keeps answering the chat."""
    who = profile_name or phone
    branch = f" ({channel['branchName']})" if channel.get("branchName") else ""
    try:
        asyncio.run(pushNotifications_sp({"pushNotifications": [{
            "action": 1,
            "companyId": channel["companyId"],
            "title": f"💬 Cliente pide atención por WhatsApp{branch}",
            "message": f"{who} ({phone}): {reason or 'quiere hablar con alguien'}. "
                       "Respóndele en el POS › Conversaciones o desde WhatsApp Business.",
            "notificationType": "Info",
            "priority": "High",
            "targetType": "Company",
            "targetCompanyId": channel["companyId"],
            # Opens the POS inbox ("Sin responder"); the phone stays out of the route (no PII in URLs).
            "navigationRoute": "/whatsapp-agent/conversations",
            "payloadJson": json.dumps({"type": "WhatsAppHandoff", "phone": phone,
                                       "channelId": channel["channelId"]}),
        }]}))
    except Exception:
        logger.exception("[whatsappReservations] handoff push failed | phone=%s", phone)
    logger.info("[whatsappReservations] handed off to staff | channel=%s phone=%s reason=%s",
                channel["channelId"], phone, reason)


_QR_CAPTION = ("Tu código QR de cliente 📲 Muéstralo en caja al pagar para que la compra "
               "quede a tu nombre y sumes tus puntos.")
_QR_NOT_FOUND = ("Todavía no tengo un QR para este número: no está registrado como cliente. "
                 "Si quieres, escríbeme *registrarme* y te doy de alta aquí mismo con "
                 "tu nombre; después ya puedes pedirme tu QR.")
_QR_AMBIGUOUS = ("Este número está registrado en más de un cliente, así que no puedo saber "
                 "cuál QR enviarte. En caja te ayudan a dejar uno solo.")
_QR_FAILED = "No pude generar tu QR en este momento. Inténtalo en un rato o pídelo en caja."


def _client_qr_png(client_id: int, first_name: str) -> bytes:
    """Same CLIENT:<id>:<name> value the app's "Mi QR" shows and the POS
    scanner reads (POSVending src/utils/clientQrPdf.ts → ClientQrScannerModal)."""
    import io
    import segno
    buf = io.BytesIO()
    segno.make(f"CLIENT:{client_id}:{(first_name or '').strip()}", error="h").save(
        buf, kind="png", scale=12, border=4)
    return buf.getvalue()


def _send_client_qr(channel: dict, phone: str) -> str | None:
    """SEND_CLIENT_QR: the sender's own client QR, matched by the phone they
    write from exactly like their points (sp_whatsappCustomerRewards). Sends
    the image itself; returns a text to add to the reply when it can't."""
    from modules.whatsappCloud import send_image  # whatsappCloud imports this module
    try:
        found = (assistant_sp("sp_whatsappCustomerRewards", {"customerRewards": [
            {"companyId": channel["companyId"], "phone": phone}]}).get("result") or [{}])[0]
    except Exception:
        logger.exception("[whatsappReservations] client lookup for QR failed | phone=%s", phone)
        return _QR_FAILED
    if found.get("status") == "not_found":
        return _QR_NOT_FOUND
    if found.get("status") == "ambiguous":
        return _QR_AMBIGUOUS
    if found.get("status") != "found" or not found.get("clientId"):
        return _QR_FAILED
    try:
        send_image(channel, phone, _client_qr_png(found["clientId"], found.get("firstName")),
                   _QR_CAPTION, filename="mi-qr.png")
    except Exception:
        logger.exception("[whatsappReservations] client QR send failed | phone=%s", phone)
        return _QR_FAILED
    logger.info("[whatsappReservations] client QR sent | channel=%s phone=%s clientId=%s",
                channel["channelId"], phone, found["clientId"])
    return None


_REGISTERED = ("✅ Listo, {name}, quedaste registrado como cliente con este número de WhatsApp. "
               "Ya sumas puntos con tus compras y puedes pedirme tu código QR cuando quieras.")
_ALREADY_REGISTERED = "Este número ya está registrado como cliente, {name}. No hace falta registrarte otra vez."
_REGISTER_AMBIGUOUS = ("Este número ya está registrado en más de un cliente. En caja te ayudan "
                       "a dejar uno solo.")
_REGISTER_FAILED = "No pude registrarte en este momento. Inténtalo en un rato o pídelo en caja."


def _split_full_name(full_name: str) -> tuple[str, str]:
    """"Ana López Ruiz" → ("Ana", "López Ruiz"). Mexican names put both last
    names at the end; a two-word first name ("María José") then lands its
    second word in last_name — staff can fix it in the POS, the phone is what
    links the client."""
    words = " ".join((full_name or "").split()).title().split(" ")
    return words[0], " ".join(words[1:])


# RECORD_DEMAND_SIGNAL: only these agent fields reach the SP. companyId,
# channelId, customerPhone, clientId and the ad attribution are set here or by
# the SP, never taken from the agent.
_DEMAND_FIELDS = ("concept", "preferredZoneText", "residenceZoneText", "workZoneText", "frequency",
                  "preferredTime", "currentSolution", "painPoint", "wouldUse", "notifyOptIn",
                  "prospectName", "preferredZoneName")


def _pin_coordinates(location: dict | None) -> dict:
    """{preferredZoneLat, preferredZoneLng} from the pin the customer shared in
    THIS message (Meta's messages[].location), or {} — never from the agent."""
    try:
        lat, lng = float(location["latitude"]), float(location["longitude"])
    except (TypeError, KeyError, ValueError):
        return {}
    if not (-90 <= lat <= 90 and -180 <= lng <= 180):
        return {}
    return {"preferredZoneLat": round(lat, 6), "preferredZoneLng": round(lng, 6)}


def _record_demand_signal(channel: dict, phone: str, fields: dict, location: dict | None = None) -> None:
    """Campaign (location validation): upserts the sender's interest in a
    service concept. Never changes what the customer gets on WhatsApp: any
    failure is logged and swallowed. sp_demandSignals links the latest ad
    attribution for this phone and channel by itself."""
    from modules.demandSignals import record_demand_signal  # lazy: keeps this module importable alone
    row = {k: fields[k] for k in _DEMAND_FIELDS if fields.get(k) is not None}
    row.update(_pin_coordinates(location))
    row.update({"companyId": channel["companyId"], "channelId": channel["channelId"],
                "customerPhone": phone})
    try:
        found = (assistant_sp("sp_whatsappCustomerRewards", {"customerRewards": [
            {"companyId": channel["companyId"], "phone": phone}]}).get("result") or [{}])[0]
        if found.get("status") == "found" and found.get("clientId"):
            row["clientId"] = found["clientId"]
    except Exception:
        logger.exception("[whatsappReservations] client lookup for demand signal failed | phone=%s", phone)
    try:
        result = record_demand_signal({"demandSignals": [row]})
        logger.info("[whatsappReservations] demand signal | channel=%s concept=%s id=%s intent=%s",
                    channel["channelId"], row.get("concept"), result.get("demandSignalId"),
                    result.get("intentLevel"))
    except Exception:
        logger.exception("[whatsappReservations] demand signal failed | channel=%s concept=%s",
                         channel["channelId"], row.get("concept"))


# RECORD_LOCATION_HOST (Red GMO): only these agent fields reach the SP. status
# and staffNotes are staff-only; tenant, channel, phone and attribution are set
# here or by the SP.
_HOST_FIELDS = ("businessName", "zoneText", "businessType", "contactName", "contactRole", "addressText",
                "openingHours", "opensWeekends", "spaceType", "dailyVisitors", "hasParking", "contactOptIn",
                "zoneName")


def _record_location_host(channel: dict, phone: str, fields: dict) -> None:
    """Red GMO: upserts a business offering space for a locker. Never changes
    what the customer gets on WhatsApp: any failure is logged and swallowed."""
    from modules.locationHosts import record_location_host  # lazy, like demand signals
    row = {k: fields[k] for k in _HOST_FIELDS if fields.get(k) is not None}
    row.update({"companyId": channel["companyId"], "channelId": channel["channelId"],
                "contactPhone": phone})
    try:
        result = record_location_host({"locationHosts": [row]})
        logger.info("[whatsappReservations] location host | channel=%s id=%s",
                    channel["channelId"], result.get("locationHostId"))
    except Exception:
        logger.exception("[whatsappReservations] location host failed | channel=%s", channel["channelId"])
        return
    if result.get("newOptIn") is True:
        _push_host_lead_to_staff(channel, phone, row, result.get("locationHostId"))


def _push_host_lead_to_staff(channel: dict, phone: str, row: dict, host_id) -> None:
    """A business said yes to being contacted about a GMO locker (Red GMO): the
    company's POS users get a push, once (sp_locationHosts newOptIn), so the
    lead isn't left sitting in the table. Failures are logged and swallowed."""
    who = row.get("contactName") or "El contacto"
    where = f" ({row['zoneText']})" if row.get("zoneText") else ""
    try:
        asyncio.run(pushNotifications_sp({"pushNotifications": [{
            "action": 1,
            "companyId": channel["companyId"],
            "title": "🏪 Negocio quiere un locker GMO",
            "message": f"{row.get('businessName')}{where}: {who} ({phone}) pidió que el equipo lo contacte. "
                       "Escríbele en el POS › Conversaciones.",
            "notificationType": "Info",
            "priority": "High",
            "targetType": "Company",
            "targetCompanyId": channel["companyId"],
            # Opens the POS inbox; the phone stays out of the route (no PII in URLs).
            "navigationRoute": "/whatsapp-agent/conversations",
            "payloadJson": json.dumps({"type": "LocationHostLead", "locationHostId": host_id,
                                       "phone": phone, "channelId": channel["channelId"]}),
        }]}))
    except Exception:
        logger.exception("[whatsappReservations] host lead push failed | host=%s", host_id)
    logger.info("[whatsappReservations] host lead pushed to staff | channel=%s host=%s",
                channel["channelId"], host_id)


def _register_client(channel: dict, phone: str, fields: dict) -> str:
    """Executes a confirmed REGISTER_CLIENT. companyId and phone come from the
    channel and the WhatsApp sender, never from the agent's fields."""
    company_id = channel["companyId"]
    first_name, last_name = _split_full_name(fields.get("fullName"))
    if not first_name or not last_name:
        return "Para registrarte necesito tu nombre y al menos un apellido. ¿Me los compartes?"
    try:
        # Same last-10-digits match as points and QR, so "+52 1 662…" and "662…" are one client.
        found = (assistant_sp("sp_whatsappCustomerRewards", {"customerRewards": [
            {"companyId": company_id, "phone": phone}]}).get("result") or [{}])[0]
    except Exception:
        logger.exception("[whatsappReservations] client lookup for registration failed | phone=%s", phone)
        return _REGISTER_FAILED
    if found.get("status") == "found":
        return _ALREADY_REGISTERED.format(name=found.get("firstName") or first_name)
    if found.get("status") == "ambiguous":
        return _REGISTER_AMBIGUOUS
    if found.get("status") != "not_found":
        return _REGISTER_FAILED

    digits = re.sub(r"\D", "", phone or "")[-10:]
    try:
        response = clients_sp({"clients": [{
            "action": 1,
            "first_name": first_name,
            "last_name": last_name,
            "clientType": "pos",
            # Trusted values, never from the agent.
            "companyId": company_id,
            "cellphone": digits,
        }]})
        row = (json.loads(response.body).get("result") or [{}])[0]
    except Exception:
        logger.exception("[whatsappReservations] client create failed | phone=%s", phone)
        return _REGISTER_FAILED
    if str(row.get("error")) == "1":
        logger.warning("[whatsappReservations] client create refused | phone=%s msg=%s", phone, row.get("msg"))
        if "already exists" in str(row.get("msg")):
            return _ALREADY_REGISTERED.format(name=first_name)
        return _REGISTER_FAILED
    logger.info("[whatsappReservations] client registered | channel=%s phone=%s",
                channel["channelId"], phone)
    return _REGISTERED.format(name=first_name)


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
            "navigationRoute": "/whatsapp-agent/conversations",
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


def _ad_context(referral: dict | None) -> dict | None:
    """What the customer saw in the ad that opened the chat (Meta sends it only
    on the first message after the click). The agent needs it because the
    greeting is often Meta's default ("Can I learn more about your business?"),
    which says nothing about the service the ad was for. Only the ad's own
    text goes out: no ids, no click ids."""
    if not referral:
        return None
    return {
        "headline": (referral.get("headline") or "")[:255] or None,
        "body": (referral.get("body") or "")[:1000] or None,
        "sourceType": referral.get("source_type"),
    }


def _client_status(company_id: int, phone: str) -> dict:
    """Is the sender a client of this company? Same phone match as points and
    QR (sp_whatsappCustomerRewards). Sent with every message so the agent's
    route — not the model — decides between the client and the prospect
    instructions. Only status and firstName leave this function."""
    try:
        row = (assistant_sp("sp_whatsappCustomerRewards", {"customerRewards": [
            {"companyId": company_id, "phone": phone}]}).get("result") or [{}])[0]
    except Exception:
        logger.exception("[whatsappReservations] client status lookup failed | phone=%s", phone)
        return {"status": "unavailable"}
    status = row.get("status")
    if status == "found":
        return {"status": "found", "firstName": row.get("firstName")}
    return {"status": status if status in ("not_found", "ambiguous") else "unavailable"}


STAFF_CONTEXT_MAX = 3
STAFF_CONTEXT_HOURS = 24


def _recent_staff_messages(company_id: int, phone: str) -> list[dict]:
    """What the team wrote to this customer (POS or WhatsApp Business app)
    since the agent's last reply, in the last 24 h, newest 3 — so the agent
    knows the customer may be answering the team ("Enrique Vizcaino /
    662…" after staff asked for name and phone, 2026-11-12). Read through
    sp_whatsappAgentConversations "thread" (the POS inbox's own view). Any
    failure → [] : it must never cost the customer their reply."""
    from datetime import datetime, timedelta, timezone
    digits = re.sub(r"\D", "", phone or "")[-10:]
    if len(digits) < 10:
        return []
    now = datetime.now(timezone.utc)
    since = (now - timedelta(hours=7) - timedelta(days=1)).date().isoformat()  # Hermosillo, UTC-7
    try:
        found = (assistant_sp("sp_whatsappAgentConversations", {"whatsappAgentConversations": [
            {"action": "thread", "companyId": company_id, "phone10": digits, "startDate": since}]})
            .get("result") or [{}])[0]
    except Exception:
        logger.exception("[whatsappReservations] staff context lookup failed | phone=%s", phone)
        return []
    staff = []
    for item in found.get("items") or []:  # oldest first
        if item.get("kind") == "bot":
            staff = []  # only what came after the agent's last reply
        elif item.get("kind") in ("staff", "staff_app") and (item.get("text") or "").strip():
            try:
                at = datetime.fromisoformat(str(item.get("atUtc")).replace("Z", "")).replace(tzinfo=timezone.utc)
            except ValueError:
                continue
            if now - at <= timedelta(hours=STAFF_CONTEXT_HOURS):
                staff.append({"text": item["text"].strip()[:500], "atUtc": item.get("atUtc")})
    return staff[-STAFF_CONTEXT_MAX:]


def _ask_agent(channel: dict, phone: str, profile_name: str | None, text: str,
               last_booked: dict | None, ad_referral: dict | None = None,
               location: dict | None = None, client: dict | None = None,
               staff_messages: list | None = None) -> tuple[str, dict | None]:
    request_body = {
        "companyId": channel["companyId"],
        "companyName": channel.get("companyName"),
        "branchId": channel.get("branchId"),
        "branchName": channel.get("branchName"),
        "phone": phone,
        "customerName": profile_name,
        "message": text,
        "recentReservation": last_booked,
        "adReferral": _ad_context(ad_referral),
        # Only the place's name/address: the coordinates never go to the model
        # (or to this call's log); they're attached when the signal is recorded.
        "sharedLocation": ({"name": location.get("name"), "address": location.get("address")}
                           if location else None),
        "client": client,
        # The team's messages since the agent's last reply: the customer may be answering them.
        "staffMessages": staff_messages or None,
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
             on_answering=None, ad_referral: dict | None = None,
             location: dict | None = None) -> str | None:
    """Returns the text to send back, or None to stay silent. on_answering()
    runs once the bot knows it will answer (whatsappCloud shows "escribiendo…").
    ad_referral is Meta's messages[].referral when this message came from an
    ad click, so the agent knows which campaign the lead is for. location is
    Meta's messages[].location when the customer shared a pin."""
    if not AGENT_URL:
        return None
    channel_id = channel["channelId"]
    state = whatsappChannels.get_state(channel_id, phone)
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
        registering = pending.get("capability") == "REGISTER_CLIENT"
        if decision == "confirm":
            if registering:
                return _register_client(channel, phone, pending)
            return _book(channel, phone, profile_name, pending)
        if decision == "cancel":
            if registering:
                return "Cancelado, no te registré. Si cambias de opinión, escríbeme *registrarme*."
            return "Cancelado, no se hizo la reservación. ¿Te ayudo con otro horario?"

    try:
        reply, pending_action = _ask_agent(channel, phone, profile_name, text, state["lastBooked"],
                                           ad_referral, location,
                                           _client_status(channel["companyId"], phone),
                                           _recent_staff_messages(channel["companyId"], phone))
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
    elif capability == "REGISTER_CLIENT":
        # Stored with its capability so the "sí" registers instead of booking.
        # Only the name is kept: phone and companyId are attached on execution.
        whatsappChannels.set_pending(channel_id, phone, {
            "capability": "REGISTER_CLIENT",
            "fullName": (pending_action.get("fields") or {}).get("fullName"),
        }, PENDING_TTL_SECONDS)
    elif capability == "RECORD_DEMAND_SIGNAL":
        # No "sí": it only records what the customer just told us (campaign,
        # location validation). The agent's reply goes out either way.
        _record_demand_signal(channel, phone, pending_action.get("fields") or {}, location)
    elif capability == "RECORD_LOCATION_HOST":
        # Red GMO partner side, same no-confirmation rule.
        _record_location_host(channel, phone, pending_action.get("fields") or {})
    elif capability == "SEND_CLIENT_QR":
        # No "sí" either: it only shows the customer their own QR. The image
        # (with its caption) goes out first; the agent's text follows — it
        # never talks about the QR itself, and may answer more ("2,7"). When
        # there's no QR, the reason leads the reply.
        problem = _send_client_qr(channel, phone)
        if problem:
            return f"{problem}\n\n{reply}" if reply else problem
    return reply
