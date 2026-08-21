"""
arcadeTicket — ticket de compra de fichas: HTML, ADLS y correo.

Reusa la infraestructura que ya existe (CLAUDE.md §3):
  * modules/ticket_receipts.save_receipt_html  -> sube el HTML a Azure Blob
  * SMTP por variables de entorno              -> manda el correo

NOMBRE DE BLOB ALEATORIO, a proposito. build_receipt_blob_path() por defecto
usa `receipt_{id}.html` con ids secuenciales, y el contenedor 'ticketspos'
esta con acceso publico 'blob': con un nombre predecible cualquiera podria
contar hacia arriba y leer tickets ajenos. Un uuid4 corta esa enumeracion sin
tocar el contenedor ni el flujo de ingresos que ya vive ahi.

TODO ES BEST-EFFORT: si falla el HTML, el blob o el correo, la compra YA se
acredito y no se toca. Un ticket que no llega es molesto; perder fichas
pagadas seria grave.
"""

import os
import smtplib
import ssl
import threading
import uuid
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import certifi

from modules.ticket_receipts import save_receipt_html
from observability import log_workflow_step

WORKFLOW = "arcade_store"


def _money(amount: float, currency: str = "MXN") -> str:
    return f"${amount:,.2f} {currency}"


def _fee_rows(ticket: dict) -> str:
    """
    Desglose de la comision de Stripe.

    OJO con la lectura: en una recarga de cartera la comision SI le baja el
    saldo al cliente, pero aqui NO — las fichas del paquete se entregan
    completas y la comision sale del ingreso de SmartLoans. Por eso la fila
    dice "Neto para SmartLoans" y se aclara abajo, para que nadie lea que le
    dieron menos fichas por culpa de la comision.
    """
    fee = ticket.get("feeMXN")
    if fee is None:
        return ""
    net = ticket.get("netMXN")
    pct = ticket.get("feePct")
    etiqueta = f"Comisión de procesamiento{f' ({pct})' if pct else ''}"
    filas = (
        f'<tr><td style="padding:8px 0;color:#6b7280">{etiqueta}</td>'
        f'<td style="padding:8px 0;text-align:right;color:#6b7280">-{_money(fee)}</td></tr>'
    )
    if net is not None:
        filas += (
            '<tr><td style="padding:8px 0;color:#6b7280">Neto para SmartLoans</td>'
            f'<td style="padding:8px 0;text-align:right">{_money(net)}</td></tr>'
        )
    return filas


def build_ticket_html(ticket: dict) -> str:
    """
    Ticket en HTML. Sin CSS externo ni imagenes remotas: se ve igual abierto
    desde el correo, desde el navegador o guardado a disco.
    """
    fecha = ticket.get("fecha") or datetime.utcnow().strftime("%d/%m/%Y %H:%M UTC")
    chips = f"{ticket['chips']:,}".replace(",", ",")
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Ticket {ticket['folio']} — SmartLoans Arcade</title></head>
<body style="margin:0;padding:24px;background:#f4f5fa;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1f2333">
  <div style="max-width:520px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 10px rgba(20,20,60,.08)">
    <div style="background:linear-gradient(115deg,#3b5bfd,#6d4aff 55%,#8b46f0);color:#fff;padding:24px">
      <div style="font-size:12px;letter-spacing:.1em;text-transform:uppercase;opacity:.85">SmartLoans Arcade</div>
      <div style="font-size:22px;font-weight:800;margin-top:4px">Ticket de compra</div>
      <div style="font-size:13px;opacity:.9;margin-top:2px">Folio {ticket['folio']}</div>
    </div>

    <div style="padding:22px 24px">
      <table style="width:100%;border-collapse:collapse;font-size:14px">
        <tr><td style="padding:8px 0;color:#6b7280">Concepto</td>
            <td style="padding:8px 0;text-align:right;font-weight:600">{ticket['concepto']}</td></tr>
        <tr><td style="padding:8px 0;color:#6b7280">Fichas acreditadas</td>
            <td style="padding:8px 0;text-align:right;font-weight:700">{chips}</td></tr>
        <tr><td style="padding:8px 0;color:#6b7280">Importe cobrado</td>
            <td style="padding:8px 0;text-align:right;font-weight:700">{_money(ticket['amount'], ticket.get('currency', 'MXN'))}</td></tr>
        {_fee_rows(ticket)}
        <tr><td style="padding:8px 0;color:#6b7280">Fecha</td>
            <td style="padding:8px 0;text-align:right">{fecha}</td></tr>
        <tr><td style="padding:8px 0;color:#6b7280">Referencia</td>
            <td style="padding:8px 0;text-align:right;font-family:monospace;font-size:12px">{ticket['reference']}</td></tr>
      </table>

      {'<div style="margin-top:10px;color:#9aa1ad;font-size:11.5px;line-height:1.5">La comisión de procesamiento la absorbe SmartLoans: tus fichas se acreditan completas.</div>' if ticket.get("feeMXN") is not None else ''}

      <div style="margin-top:18px;padding:14px;border-radius:12px;background:#eef0f6;color:#6b7280;font-size:12.5px;line-height:1.5">
        Las fichas son solo para jugar dentro del arcade.
        <strong style="color:#374151">No son dinero, no se canjean y no se reembolsan en efectivo.</strong>
      </div>

      <div style="margin-top:14px;color:#9aa1ad;font-size:11.5px;line-height:1.5">
        Este comprobante se genera automaticamente. Si no reconoces esta compra,
        responde a este correo.
      </div>
    </div>
  </div>
</body></html>"""


def _upload_ticket(purchase_id: int, company_id: int, html: str) -> str | None:
    """
    Sube el ticket a ADLS con nombre IMPREDECIBLE.

    El uuid4 no es adorno: el contenedor es de lectura publica y un
    `receipt_{id}.html` secuencial se puede enumerar.
    """
    stamp = datetime.utcnow()
    file_name = f"arcade_{stamp:%Y%m%d}_{uuid.uuid4().hex}.html"
    try:
        result = save_receipt_html(
            income_id=int(purchase_id),
            branch_id=int(company_id),
            html=html,
            file_name=file_name,
        )
        return result.get("receiptUrl")
    except Exception as e:
        print(f"[arcadeTicket] no se pudo subir el ticket {purchase_id}: {type(e).__name__}: {e}")
        return None


def _send_ticket_email(to_email: str, name: str, ticket: dict, html: str, url: str | None) -> bool:
    """Manda el ticket por correo, con el HTML incrustado y el enlace a ADLS."""
    server = os.getenv("SMTP_SERVER", "smtp.office365.com")
    port = int(os.getenv("SMTP_PORT", "587"))
    sender = os.getenv("SMTP_USER", "")
    password = os.getenv("SMTP_PASSWORD", "")

    if not (sender and password):
        print("[arcadeTicket] SMTP sin configurar — ticket no enviado")
        return False
    if "@" not in (to_email or ""):
        print(f"[arcadeTicket] cliente sin correo — ticket {ticket['folio']} no enviado")
        return False

    msg = MIMEMultipart("alternative")
    msg["From"] = sender
    msg["To"] = to_email
    msg["Subject"] = f"Ticket {ticket['folio']} — {ticket['chips']:,} fichas"

    texto = (
        f"Hola {name or 'jugador'},\n\n"
        f"Tu compra de fichas fue procesada.\n\n"
        f"Folio: {ticket['folio']}\n"
        f"Concepto: {ticket['concepto']}\n"
        f"Fichas: {ticket['chips']:,}\n"
        f"Importe cobrado: {_money(ticket['amount'], ticket.get('currency', 'MXN'))}\n"
    )
    if ticket.get("feeMXN") is not None:
        pct = f" ({ticket['feePct']})" if ticket.get("feePct") else ""
        texto += f"Comision de procesamiento{pct}: -{_money(ticket['feeMXN'])}\n"
        if ticket.get("netMXN") is not None:
            texto += f"Neto para SmartLoans: {_money(ticket['netMXN'])}\n"
        texto += "La comision la absorbe SmartLoans: tus fichas se acreditan completas.\n"
    texto += (
        f"Referencia: {ticket['reference']}\n"
    )
    if url:
        texto += f"\nVer el ticket: {url}\n"
    texto += "\nLas fichas son solo para jugar. No son dinero y no se canjean.\n"

    msg.attach(MIMEText(texto, "plain", "utf-8"))
    msg.attach(MIMEText(html, "html", "utf-8"))

    try:
        context = ssl.create_default_context(cafile=certifi.where())
        with smtplib.SMTP(server, port) as smtp:
            smtp.ehlo()
            smtp.starttls(context=context)
            smtp.ehlo()
            smtp.login(sender, password)
            smtp.sendmail(sender, [to_email], msg.as_string())
        return True
    except Exception as e:
        print(f"[arcadeTicket] fallo el envio del ticket {ticket['folio']}: {type(e).__name__}: {e}")
        return False


def issue_ticket_async(ticket: dict, contact: dict, on_stored) -> None:
    """
    Genera, sube y manda el ticket en un HILO APARTE.

    La compra ya se acredito antes de llegar aqui: el jugador no tiene por que
    esperar a que respondan Azure y el servidor de correo para ver sus fichas.
    """
    def _run():
        try:
            html = build_ticket_html(ticket)
            url = _upload_ticket(ticket["purchaseId"], ticket["companyId"], html)
            sent = _send_ticket_email(
                contact.get("email", ""), contact.get("name", ""), ticket, html, url,
            )
            on_stored(ticket["purchaseId"], url, sent)
            log_workflow_step(
                "Chip Ticket Issued", workflow_name=WORKFLOW, action="receipt",
                entity="arcadePurchases", entity_id=ticket["purchaseId"],
                status="SUCCESS" if sent else "FAILURE",
                message=f"{ticket['folio']} — blob={'ok' if url else 'fallo'} correo={'ok' if sent else 'fallo'}",
            )
        except Exception as e:
            print(f"[arcadeTicket] ticket fallido (no afecta la compra): {type(e).__name__}: {e}")

    threading.Thread(target=_run, daemon=True).start()
