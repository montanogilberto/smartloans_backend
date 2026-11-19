"""
RFC-014 (POSVending docs/rfcs/RFC-014-loan-transaction-tickets.md) — a ticket
for every money event of a loan, like GMO POS does for a sale.

Phase 1: funding DECLARED (lender declares the SPEI) and CONFIRMED (borrower
confirms it arrived).

Push is the CORE channel between the parties (modules/loanPush.py, and the
direct send_azure_push in fundingTransactions). Tickets complement it:

Each event, for each party:
  * WhatsApp -> SMS through notificationDispatch ONLY when the party has no
    app device (uninstalled / never installed / no app user) — app users get
    the core push instead, so nobody pays for a message they already saw.
    The dispatcher logs every send and never re-sends an event. One eventName
    per recipient (funding_declared_lender, ...): the dispatcher's
    idempotency key has no recipient (RFC-014 P4).
  * WhatsApp uses the approved generic Utility template `comprobante_listo`
    ({{1}} detail, {{2}} link). If Meta refuses it, the cascade moves to SMS.
  * an email with the same ticket, when the client has one (durable copy).

The ticket is a signed link /comprobante/{token} whose page is rendered when
it's opened, from rows that already exist (fundingTransactions, paymentHistory,
transferEvidence) — no table, no stored file. It always shows the current
status and history.

Non-custodial (D1): the ticket documents a declaration/confirmation between
the parties; it never says GMO Prestamos moved, received or holds money.
Best-effort: nothing here ever changes a funding response.

Env vars:
  LOAN_TICKET_LINK_SECRET  long random string; unset -> no links are issued
                           and every link is rejected (fails closed). Rotating
                           it invalidates every loan ticket link (only these).
  BACKEND_PUBLIC_URL       default https://smartloansbackend.azurewebsites.net
"""
import asyncio
import base64
import hashlib
import hmac
import html
import json
import logging
import os
import re
import threading
from datetime import datetime, timedelta, timezone

logger = logging.getLogger(__name__)

APP_NAME = "GMO Prestamos"
WA_TEMPLATE = "comprobante_listo"
LEGEND = (f"Este comprobante documenta una declaración o confirmación entre las partes. "
          f"{APP_NAME} no recibe, retiene ni administra estos fondos.")

# Token kind -> (dispatcher sourceType, paymentHistory subjectType, transferEvidence referenceType)
KINDS = {"funding": ("fundingTransaction", "FUNDING", "FUNDING")}
RECIPIENTS = ("borrower", "lender")
EVENTS = ("declared", "confirmed")

_TOKEN_RE = re.compile(r"^(\d+)-([a-z]+)-(\d+)-(borrower|lender)-([A-Za-z0-9_-]{22})$")

_STATUS_LABELS = {
    "PENDING_CONFIRMATION": "Pendiente de confirmar",
    "CONFIRMED": "Confirmado",
    "REJECTED": "Rechazado",
    "ESCALATED": "En revisión por soporte",
    "DISPUTED": "En disputa",
    "CANCELLED": "Cancelado",
}


# ── Signed links ─────────────────────────────────────────────────────────────

def _secret() -> bytes:
    return os.getenv("LOAN_TICKET_LINK_SECRET", "").encode()


def _signature(company_id: int, kind: str, source_id: int, recipient: str) -> str:
    # Domain-separated ("loanticket:") so a POS /recibo signature can never be
    # replayed here even if both secrets were ever the same value.
    msg = f"loanticket:{company_id}:{kind}:{source_id}:{recipient}".encode()
    digest = hmac.new(_secret(), msg, hashlib.sha256).digest()
    return base64.urlsafe_b64encode(digest).decode()[:22]


def ticket_link(company_id, kind: str, source_id, recipient: str) -> str | None:
    """Customer-facing link for this party's ticket, or None if links are off."""
    if not _secret():
        logger.warning("[loanTickets] LOAN_TICKET_LINK_SECRET not set — no ticket link issued")
        return None
    if kind not in KINDS or recipient not in RECIPIENTS:
        return None
    company_id, source_id = int(company_id), int(source_id)
    base = os.getenv("BACKEND_PUBLIC_URL", "https://smartloansbackend.azurewebsites.net").rstrip("/")
    sig = _signature(company_id, kind, source_id, recipient)
    return f"{base}/comprobante/{company_id}-{kind}-{source_id}-{recipient}-{sig}"


def verify_token(token: str):
    """(companyId, kind, sourceId, recipient) for a valid token, else None."""
    if not _secret():
        return None
    match = _TOKEN_RE.match(token or "")
    if not match:
        return None
    company_id, kind, source_id, recipient, sig = (
        int(match.group(1)), match.group(2), int(match.group(3)), match.group(4), match.group(5))
    if kind not in KINDS:
        return None
    if not hmac.compare_digest(sig, _signature(company_id, kind, source_id, recipient)):
        return None
    return company_id, kind, source_id, recipient


# ── Data (every read through the existing SP wrappers) ───────────────────────

def _body(response) -> dict | list:
    try:
        return json.loads(response.body)
    except Exception:
        return {}


def _funding_one(company_id: int, funding_id: int) -> dict:
    from modules.fundingTransactions import _sp_raw  # lazy: fundingTransactions imports this module
    row = _sp_raw({"fundingTransactions": [{
        "action": "one", "companyId": company_id, "fundingTransactionId": funding_id}]})
    return row if isinstance(row, dict) and row.get("fundingTransactionId") else {}


def _history(company_id: int, subject_type: str, subject_id: int) -> list:
    from modules.paymentHistory import payment_history_all_sp
    data = _body(payment_history_all_sp({"paymentHistory": [{
        "companyId": company_id, "subjectType": subject_type, "subjectId": subject_id}]}))
    return data if isinstance(data, list) else []


def _evidence(company_id: int, reference_type: str, reference_id: int) -> dict:
    from modules.transferEvidence import transfer_evidence_sp
    data = _body(transfer_evidence_sp({"transferEvidence": [{
        "action": "list", "companyId": company_id,
        "referenceType": reference_type, "referenceId": reference_id}]}))
    return data[0] if isinstance(data, list) and data else {}


def _contact(client_id) -> dict:
    """{email, phone (E.164), name} — empty values when unknown."""
    from modules.loanOffers import _offer_contact
    from modules.users import _normalize_phone
    c = _offer_contact(client_id) or {}
    phone = ""
    if c.get("cellphone"):
        try:
            phone = _normalize_phone(c["cellphone"])
        except Exception:
            phone = ""
    return {"email": c.get("email") or "", "phone": phone, "name": c.get("name") or ""}


# ── Formatting ───────────────────────────────────────────────────────────────

def _money(amount) -> str:
    try:
        return f"${float(amount):,.2f} MXN"
    except (TypeError, ValueError):
        return "—"


def _hermosillo(iso: str | None) -> str:
    """'19/11/2026 14:35' in Hermosillo (UTC-7, no DST). Backend times are UTC."""
    if not iso:
        return "—"
    try:
        dt = datetime.fromisoformat(str(iso).replace("Z", "")).replace(tzinfo=timezone.utc)
        return (dt - timedelta(hours=7)).strftime("%d/%m/%Y %H:%M")
    except ValueError:
        return str(iso)


def _messages(event: str, recipient: str, ft: dict, loan_status: str | None) -> dict:
    """title (push/email subject), detail (WhatsApp {{1}} / SMS / push body)."""
    amount, loan_id, folio = _money(ft.get("amountMXN")), ft.get("loanId"), ft.get("fundingTransactionId")
    if event == "declared":
        if recipient == "lender":
            return {"title": "Fondeo declarado",
                    "detail": f"Declaraste el fondeo de {amount} del préstamo #{loan_id}. Folio {folio}. "
                              f"Falta que el acreditado confirme que lo recibió."}
        return {"title": "Confirma tu fondeo",
                "detail": f"Tu prestamista declaró que te transfirió {amount} (préstamo #{loan_id}, folio {folio}). "
                          f"Revisa tu banco y confirma en la app si llegó."}
    if loan_status == "active":
        return {"title": "Préstamo activo",
                "detail": f"Fondeo de {amount} confirmado. El préstamo #{loan_id} está activo. Folio {folio}."}
    return {"title": "Fondeo confirmado",
            "detail": f"Fondeo de {amount} confirmado para el préstamo #{loan_id}. Folio {folio}. "
                      f"El calendario de pagos está en revisión."}


# ── Notify ───────────────────────────────────────────────────────────────────

def _has_app(client_id) -> bool:
    """True when the client has an app user with a device the hub reaches.
    Unknown (lookup failed) counts as no app, so the ticket still goes out."""
    try:
        from databases import connection
        from modules.pushNotifications import resolve_push_user_ids
        from modules.azure_notifications import has_push_device
        conn = connection()
        try:
            user_id = resolve_push_user_ids(conn.cursor(), [client_id]).get(int(client_id))
        finally:
            conn.close()
        if not user_id:
            return False
        return bool(asyncio.run(has_push_device(user_id)).get("registered"))
    except Exception as e:
        logger.warning("[loanTickets] device check failed for clientId=%s: %s", client_id, e)
        return False


def _dispatch(payload: dict) -> None:
    from modules.notificationDispatch import dispatch_notification_connector
    response = asyncio.run(dispatch_notification_connector(payload))
    # Ids and status only — never the phone or the message body.
    logger.info("[loanTickets] dispatch %s/%s %s -> HTTP %s", payload["sourceType"], payload["sourceId"],
                payload["eventName"], getattr(response, "status_code", "?"))


def _email(contact: dict, title: str, detail: str, link: str | None, folio) -> None:
    if not contact.get("email"):
        return
    from modules.users import _send_email
    lines = [f"Hola {contact.get('name') or ''},".replace(" ,", ","), "", detail, ""]
    if link:
        lines += ["Consulta tu comprobante aquí:", link, ""]
    lines += [LEGEND, "", f"— {APP_NAME}"]
    _send_email(contact["email"], f"{APP_NAME} — {title} · Folio {folio}", "\n".join(lines))


def notify_funding_event(company_id, funding_id, event: str, loan_status: str | None = None) -> None:
    """Ticket for both parties of a funding event. Synchronous; callers run it
    in a background thread (notify_funding_event_async)."""
    if event not in EVENTS:
        raise ValueError(f"unknown funding event {event!r}")
    company_id, funding_id = int(company_id), int(funding_id)
    ft = _funding_one(company_id, funding_id)
    if not ft:
        logger.warning("[loanTickets] funding %s not found — no ticket", funding_id)
        return
    for recipient, client_id in (("lender", ft.get("lenderClientId")), ("borrower", ft.get("borrowerClientId"))):
        if not client_id:
            continue
        try:
            contact = _contact(client_id)
            msg = _messages(event, recipient, ft, loan_status)
            link = ticket_link(company_id, "funding", funding_id, recipient)
            _email(contact, msg["title"], msg["detail"], link, funding_id)
            if _has_app(client_id):
                logger.info("[loanTickets] funding %s %s %s: has the app — core push only, no WhatsApp/SMS",
                            funding_id, event, recipient)
                continue
            _dispatch({
                "companyId": company_id,
                "sourceType": KINDS["funding"][0],
                "sourceId": funding_id,
                "recipientType": "client",
                "recipientId": int(client_id),
                "eventName": f"funding_{event}_{recipient}",
                "phone": contact["phone"],
                "pushTitle": msg["title"],
                "pushMessage": msg["detail"],
                "waSmsMessage": f"{APP_NAME}: {msg['detail']}",
                "messagePreview": msg["detail"],
                "receiptUrl": link,
                "waTemplate": WA_TEMPLATE,
                "waParams": [msg["detail"], link or f"la app {APP_NAME}"],
                "navigationRoute": f"/loan-detail/{ft.get('loanId')}",
            })
        except Exception as e:
            logger.error("[loanTickets] funding %s %s %s failed: %s", funding_id, event, recipient, e)


def notify_funding_event_async(company_id, funding_id, event: str, loan_status: str | None = None) -> None:
    """Fire-and-forget (D7): the funding response never waits on, or fails by, a notice."""
    threading.Thread(target=notify_funding_event, args=(company_id, funding_id, event, loan_status),
                     daemon=True).start()


# ── Ticket page ──────────────────────────────────────────────────────────────

def render_funding_ticket(company_id: int, funding_id: int, recipient: str) -> str | None:
    """HTML of the funding ticket for one party, or None if it doesn't exist."""
    ft = _funding_one(company_id, funding_id)
    if not ft:
        return None
    _, subject_type, reference_type = KINDS["funding"]
    history = _history(company_id, subject_type, funding_id)
    evidence = _evidence(company_id, reference_type, funding_id)
    status = _STATUS_LABELS.get(str(ft.get("status")), str(ft.get("status") or "—"))
    role = "Prestamista" if recipient == "lender" else "Acreditado"
    e = html.escape

    rows = [
        ("Folio", str(ft.get("fundingTransactionId"))),
        ("Préstamo", f"#{ft.get('loanId')}"),
        ("Concepto", "Fondeo del préstamo por SPEI directo"),
        ("Monto", _money(ft.get("amountMXN"))),
        ("Fecha de la transferencia", _hermosillo(ft.get("transferDate"))),
        ("Declarado", _hermosillo(ft.get("declaredAt"))),
        ("Confirmado", _hermosillo(ft.get("confirmedAt"))),
        ("Estado", status),
    ]
    if evidence:
        rows += [("Clave de rastreo", evidence.get("claveRastreo") or "—"),
                 ("Banco de origen", evidence.get("bankFrom") or "—")]
        if evidence.get("validationStatus"):
            rows.append(("Comprobante revisado por IA", str(evidence["validationStatus"])))
    table = "".join(f"<tr><th>{e(k)}</th><td>{e(str(v))}</td></tr>" for k, v in rows if v not in (None, ""))

    steps = "".join(
        f"<li><strong>{e(_STATUS_LABELS.get(str(h.get('newStatus')), str(h.get('newStatus') or '')))}</strong>"
        f" · {e(_hermosillo(h.get('created_At') or h.get('changedAt')))}</li>"
        for h in history
    )
    history_block = f"<h2>Historial</h2><ol>{steps}</ol>" if steps else ""

    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Comprobante · Folio {e(str(ft.get('fundingTransactionId')))}</title>
<style>body{{font-family:system-ui,sans-serif;max-width:440px;margin:32px auto;padding:0 16px;color:#1f2937}}
h1{{font-size:20px;margin:0 0 4px}}.sub{{color:#6b7280;margin:0 0 16px}}
table{{width:100%;border-collapse:collapse}}th,td{{text-align:left;padding:8px 4px;border-bottom:1px solid #e5e7eb;font-size:15px}}
th{{color:#6b7280;font-weight:500;width:46%}}h2{{font-size:16px;margin:20px 0 6px}}ol{{padding-left:20px;margin:0}}
li{{margin:4px 0;font-size:14px}}.note{{margin-top:20px;padding:12px;border-radius:8px;background:#ecfdf5;color:#065f46;font-size:13px}}</style>
</head><body>
<h1>{e(APP_NAME)} · Comprobante de fondeo</h1>
<p class="sub">{e(role)}</p>
<table>{table}</table>
{history_block}
<p class="note">{e(LEGEND)}</p>
</body></html>"""
