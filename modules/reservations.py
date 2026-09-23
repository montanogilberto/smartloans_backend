"""
Laundry service reservations — customers book lavado/secado from the kiosk.
Staff confirms via POS. Sends SMS + WhatsApp + email on creation.
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
from fastapi.responses import JSONResponse
from databases import connection
from modules.ticket_notifications import send_sms, send_whatsapp

logger = logging.getLogger(__name__)

COMPANY_NAME = os.getenv("COMPANY_NAME", "Lavandería GMO")


def _conn():
    return connection()


def _sp(json_file: dict):
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_reservations] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


def _send_confirmation_sms(phone: str, name: str, service: str, date: str, time_slot: str, reservation_id: int):
    service_label = "Lavado" if service == "lavado" else "Secado"
    body = (
        f"✅ Reservación confirmada - {COMPANY_NAME}\n"
        f"Hola {name}! Tu reservación para {service_label} está lista.\n"
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
    service_label = "Lavado" if service == "lavado" else "Secado"
    body = (
        f"✅ *Reservación confirmada - {COMPANY_NAME}*\n\n"
        f"Hola *{name}*! Tu reservación para *{service_label}* está lista.\n\n"
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

    service_label = "Lavado" if service == "lavado" else "Secado"
    detail_line = f"<p><strong>Servicio:</strong> {detail}</p>" if detail else ""

    subject = f"✅ Reservación #{reservation_id} — {COMPANY_NAME}"
    html = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;background:#f9f9f9;border-radius:12px">
      <h2 style="color:#0a2d6e">¡Reservación Confirmada!</h2>
      <p>Hola <strong>{name}</strong>,</p>
      <p>Tu reservación en <strong>{COMPANY_NAME}</strong> ha sido registrada con éxito.</p>
      <table style="border-collapse:collapse;width:100%">
        <tr><td style="padding:8px 0;color:#555">Servicio</td><td><strong>{service_label}</strong></td></tr>
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


def reservations_sp(json_file: dict):
    try:
        result = _sp(json_file)

        # On successful create (action 1), fire notifications asynchronously-ish
        action = None
        try:
            action = json_file.get("reservations", [{}])[0].get("action")
        except Exception:
            pass

        if action == 1 and isinstance(result, dict) and "result" in result:
            row = result["result"][0] if result["result"] else {}
            res_id = row.get("reservationId")
            if res_id and "error" not in row:
                payload = json_file.get("reservations", [{}])[0]
                phone    = payload.get("phone", "")
                name     = payload.get("clientName", "")
                service  = payload.get("serviceType", "")
                date     = payload.get("reservationDate", "")
                slot     = payload.get("timeSlot", "")
                detail   = payload.get("serviceDetail")
                email    = payload.get("email")

                _send_confirmation_sms(phone, name, service, date, slot, res_id)
                _send_confirmation_whatsapp(phone, name, service, date, slot, res_id)
                if email:
                    _send_confirmation_email(email, name, service, date, slot, res_id, detail)

        return JSONResponse(result, status_code=200)
    except Exception as e:
        logger.exception("[reservations] unhandled error")
        return JSONResponse({"error": str(e)}, status_code=500)


def run_migration():
    """Create the reservations table and sp_reservations SP if they don't exist."""
    sql_path = os.path.join(os.path.dirname(__file__), "..", "sql", "migrations", "2026-09-23_add_reservations.sql")
    with open(os.path.abspath(sql_path), encoding="utf-8") as f:
        script = f.read()

    # Split on GO (batch separator used by SQL Server)
    batches = [b.strip() for b in script.split("\nGO") if b.strip()]
    executed = []
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        for batch in batches:
            if batch:
                cursor.execute(batch)
        conn.commit()
        executed = batches
    finally:
        if conn:
            conn.close()

    # Now create/replace the SP from the full sp_reservations.sql
    sp_path = os.path.join(os.path.dirname(__file__), "..", "sql", "sp_reservations.sql")
    with open(os.path.abspath(sp_path), encoding="utf-8") as f:
        sp_script = f.read()

    sp_batches = [b.strip() for b in sp_script.split("\nGO") if b.strip()]
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        for batch in sp_batches:
            if batch:
                cursor.execute(batch)
        conn.commit()
    finally:
        if conn:
            conn.close()

    return {"ok": True, "batches_run": len(executed) + len(sp_batches)}
