"""
Reservations — customers book a slot for a service from the company's
catalog (sp_reservationServices) via kiosk or WhatsApp; hours come from
sp_reservationHours. Staff confirms via POS. On creation: SMS + WhatsApp +
email to the customer and a push to the company's POS users.
"""

import json
import logging
import os
import ssl
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Optional

import certifi
from fastapi import BackgroundTasks
from fastapi.responses import JSONResponse
from databases import connection
from modules.pushNotifications import pushNotifications_sp
from modules.ticket_notifications import send_sms, send_whatsapp

logger = logging.getLogger(__name__)

COMPANY_NAME = os.getenv("COMPANY_NAME", "Lavandería GMO")


def _conn():
    return connection()


def _sp(json_file: dict, procedure: str = "sp_reservations"):
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{procedure}] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


def _send_confirmation_sms(phone: str, name: str, service: str, date: str, time_slot: str, reservation_id: int):
    body = (
        f"✅ Reservación confirmada - {COMPANY_NAME}\n"
        f"Hola {name}! Tu reservación para {service} está lista.\n"
        f"📅 Fecha: {date}  🕐 Hora: {time_slot}\n"
        f"Folio: #{reservation_id}\n"
        f"Te esperamos. Para cancelar responde CANCELAR."
    )
    try:
        send_sms(phone, body)
        logger.info("[reservations] SMS sent to %s for reservation #%d", phone, reservation_id)
    except Exception as e:
        logger.warning("[reservations] SMS failed: %s", e)


def _send_confirmation_whatsapp(phone: str, name: str, service: str, date: str, time_slot: str, reservation_id: int):
    body = (
        f"✅ *Reservación confirmada - {COMPANY_NAME}*\n\n"
        f"Hola *{name}*! Tu reservación para *{service}* está lista.\n\n"
        f"📅 *Fecha:* {date}\n"
        f"🕐 *Hora:* {time_slot}\n"
        f"🔖 *Folio:* #{reservation_id}\n\n"
        f"Te esperamos. Para cancelar responde CANCELAR."
    )
    try:
        send_whatsapp(phone, body)
        logger.info("[reservations] WhatsApp sent to %s for reservation #%d", phone, reservation_id)
    except Exception as e:
        logger.warning("[reservations] WhatsApp failed: %s", e)


def _send_confirmation_email(email: str, name: str, service: str, date: str, time_slot: str, reservation_id: int, detail: Optional[str]):
    smtp_server = os.getenv("SMTP_SERVER", "smtp.office365.com")
    port = int(os.getenv("SMTP_PORT", "587"))
    sender = os.getenv("SMTP_USER", "")
    password = os.getenv("SMTP_PASSWORD", "")
    if not sender or not password:
        logger.warning("[reservations] SMTP not configured, skipping email")
        return

    detail_line = f"<p><strong>Servicio:</strong> {detail}</p>" if detail else ""

    subject = f"✅ Reservación #{reservation_id} — {COMPANY_NAME}"
    html = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;background:#f9f9f9;border-radius:12px">
      <h2 style="color:#0a2d6e">¡Reservación Confirmada!</h2>
      <p>Hola <strong>{name}</strong>,</p>
      <p>Tu reservación en <strong>{COMPANY_NAME}</strong> ha sido registrada con éxito.</p>
      <table style="border-collapse:collapse;width:100%">
        <tr><td style="padding:8px 0;color:#555">Servicio</td><td><strong>{service}</strong></td></tr>
        {detail_line.replace('<p>','<tr><td style="padding:8px 0;color:#555">Detalle</td><td>').replace('</p>','</td></tr>') if detail else ''}
        <tr><td style="padding:8px 0;color:#555">Fecha</td><td><strong>{date}</strong></td></tr>
        <tr><td style="padding:8px 0;color:#555">Hora</td><td><strong>{time_slot}</strong></td></tr>
        <tr><td style="padding:8px 0;color:#555">Folio</td><td><strong>#{reservation_id}</strong></td></tr>
      </table>
      <p style="margin-top:24px;color:#888;font-size:13px">Si necesitas cancelar, comunícate con nosotros.</p>
    </div>
    """
    try:
        msg = MIMEMultipart("alternative")
        msg["From"] = sender
        msg["To"] = email
        msg["Subject"] = subject
        msg.attach(MIMEText(html, "html", "utf-8"))
        context = ssl.create_default_context(cafile=certifi.where())
        with smtplib.SMTP(smtp_server, port) as srv:
            srv.ehlo(); srv.starttls(context=context); srv.ehlo()
            srv.login(sender, password)
            srv.sendmail(sender, [email], msg.as_string())
        logger.info("[reservations] email sent to %s for reservation #%d", email, reservation_id)
    except Exception as e:
        logger.warning("[reservations] email failed: %s", e)


def _first_reservation(result) -> dict:
    """sp_reservations returns {"result":[{"reservations":[{...}]}]}."""
    try:
        return (result["result"][0].get("reservations") or [{}])[0]
    except (KeyError, IndexError, TypeError, AttributeError):
        return {}


def create_reservation(fields: dict) -> dict:
    """Runs sp_reservations action 1. Shared by the kiosk (POST /reservations)
    and the WhatsApp agent's confirmed booking, so both hit the same slot
    capacity check. Returns the created row, or {"error", "message"?} as the
    SP reported it (slot_taken, past_slot, missing fields)."""
    result = _sp({"reservations": [{**fields, "action": 1}]})
    if isinstance(result, dict) and result.get("error"):
        return result
    row = _first_reservation(result)
    if not row.get("reservationId"):
        return {"error": "unexpected response from sp_reservations"}
    return row


def list_services(company_id: int) -> list:
    """Active services of the company's catalog (sp_reservationServices)."""
    result = _sp({"reservationServices": [{"companyId": company_id}]}, "sp_reservationServices")
    try:
        return result["result"][0]["reservationServices"]
    except (KeyError, IndexError, TypeError):
        return []


def available_slots(company_id: int, date: str, reservation_service_id: int) -> dict:
    """sp_reservations action 6: {"date", "reservationServiceId", "serviceName",
    "durationMinutes", "capacity", "open", "close",
    "slots": [{"timeSlot", "available"}]} or {"error"}. open/close are null
    and slots empty on a closed day."""
    result = _sp({"reservations": [{"action": 6, "companyId": company_id, "date": date,
                                    "reservationServiceId": reservation_service_id}]})
    if isinstance(result, dict) and result.get("error"):
        return result
    try:
        return result["result"][0]
    except (KeyError, IndexError, TypeError):
        return {"error": "unexpected response from sp_reservations"}


def notify_customer(row: dict):
    """SMS + WhatsApp (Twilio) + email confirmation to the customer."""
    args = (row.get("phone", ""), row.get("clientName", ""), row.get("serviceType", ""),
            row.get("reservationDate", ""), row.get("timeSlot", ""), row["reservationId"])
    _send_confirmation_sms(*args)
    _send_confirmation_whatsapp(*args)
    if row.get("email"):
        _send_confirmation_email(row["email"], *args[1:], row.get("serviceDetail"))


async def notify_pos(row: dict, source: str = "kiosco"):
    """Push to every POS user of the company. The POS also polls action 5
    every minute; this is what makes staff notice right away."""
    company_id = row.get("companyId")
    service_label = row.get("serviceType") or ""
    try:
        await pushNotifications_sp({
            "pushNotifications": [{
                "action": 1,
                "companyId": company_id,
                "title": f"🧺 Nueva reservación #{row['reservationId']}",
                "message": (f"{row.get('clientName', '')} — {service} "
                            f"{row.get('reservationDate', '')} {row.get('timeSlot', '')} (vía {source})"),
                "notificationType": "Info",
                "priority": "High",
                "targetType": "Company",
                "targetCompanyId": company_id,
                "navigationRoute": "/reservations",
                "payloadJson": json.dumps({"type": "NewReservation", "reservationId": row["reservationId"]}),
            }]
        })
    except Exception:
        logger.exception("[reservations] POS push failed for reservation #%s", row.get("reservationId"))


def reservation_catalog_sp(json_file: dict, procedure: str):
    """Passthrough for the catalogs: sp_reservationServices / sp_reservationHours."""
    try:
        return JSONResponse(_sp(json_file, procedure), status_code=200)
    except Exception as e:
        logger.exception("[reservations] %s failed", procedure)
        return JSONResponse({"error": str(e)}, status_code=500)


def reservations_sp(json_file: dict, background_tasks: BackgroundTasks):
    try:
        payload = (json_file.get("reservations") or [{}])[0]
        if payload.get("action") == 1:
            fields = {k: v for k, v in payload.items() if k != "action"}
            row = create_reservation(fields)
            if row.get("error"):
                return JSONResponse(row, status_code=200)
            # After the response: SMTP/Twilio/push must not slow the kiosk.
            background_tasks.add_task(notify_customer, row)
            background_tasks.add_task(notify_pos, row)
            return JSONResponse({"result": [{"reservations": [row]}]}, status_code=200)

        return JSONResponse(_sp(json_file), status_code=200)
    except Exception as e:
        logger.exception("[reservations] unhandled error")
        return JSONResponse({"error": str(e)}, status_code=500)


# Run in this order: tables/migrations first, then the SPs that use them.
_MIGRATION_FILES = (
    "sql/migrations/2026-09-23_add_reservations.sql",
    "sql/migrations/2026-09-24_reservation_catalogs.sql",
    "sql/sp_reservationServices.sql",
    "sql/sp_reservationHours.sql",
    "sql/sp_reservations.sql",
)


def run_migration():
    """Create the reservation tables and SPs (idempotent). The catalog seed
    inside the migration only runs once its @companyId is filled in."""
    root = os.path.join(os.path.dirname(__file__), "..")
    batches_run = 0
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        for rel_path in _MIGRATION_FILES:
            with open(os.path.abspath(os.path.join(root, rel_path)), encoding="utf-8") as f:
                script = f.read()
            # Split on GO (batch separator used by SQL Server)
            for batch in (b.strip() for b in script.split("\nGO")):
                if batch:
                    cursor.execute(batch)
                    batches_run += 1
        conn.commit()
    finally:
        if conn:
            conn.close()
    return {"ok": True, "batches_run": batches_run}
