"""
Saldo top-ups a person confirmed. The evidence (comprobante) only proves a claim:
money is credited when a staff member says they saw it in the company's account.
Crediting, keeping the evidence and posting the accounting entry happen here so
none of the three is left to the app.
"""
import asyncio
import html
import json
import re
import uuid
from datetime import datetime
from typing import Callable, Optional
from zoneinfo import ZoneInfo
from fastapi.responses import JSONResponse
from databases import connection
from modules.companies import company_name
from modules.journalEntries import post_wallet_topup_journal_entry
from modules.ticket_receipts import save_receipt_html
from modules.transferEvidence import transfer_evidence_sp
from modules.walletTransactions import post_entry
from observability.logger import log_audit, log_workflow_step

TOPUP_REFERENCE = "WALLET_TOPUP"
# Push -> WhatsApp -> SMS ticket after every credit (policy row in
# sql/migrations/2026-11-08_wallet_topup_notification.sql).
TOPUP_EVENT = "wallet_topup_credited"
TOPUP_TEMPLATE = "abono_saldo"
METHOD_LABELS = {"transferencia": "transferencia", "efectivo": "efectivo",
                 "terminal": "tarjeta en terminal", "tarjeta": "tarjeta"}
OPERATION_PATTERN = re.compile(r"^[A-Z0-9-]{4,30}$")
Notify = Optional[Callable[[dict], None]]


def top_up_message(json_file: dict) -> str:
    """The ticket text: amount, method, company and the saldo after it."""
    amount = float(json_file.get("amountMXN") or 0)
    label = METHOD_LABELS.get(json_file.get("method"), json_file.get("method") or "")
    company = json_file.get("companyName")
    lines = [f"Abono de ${amount:,.2f} MXN" + (f" con {label}" if label else "")
             + (f" en {company}" if company else "") + "."]
    balance = json_file.get("balanceAfter")
    if isinstance(balance, (int, float)):
        lines.append(f"Saldo disponible: ${balance:,.2f} MXN")
    if json_file.get("entryId"):
        lines.append(f"Folio: {json_file['entryId']}")
    return "\n".join(lines)


def _client_phone(client_id) -> str | None:
    from modules.income import _get_client_phone  # lazy: income imports a lot
    conn = connection()
    try:
        return _get_client_phone(conn, client_id)
    finally:
        conn.close()


def _money(amount) -> str:
    return f"${float(amount or 0):,.2f} MXN"


def top_up_ticket_html(json_file: dict) -> str:
    """The top-up ticket as one self-contained HTML page (no external CSS or
    images), the same kind of page the POS stores for a sale."""
    esc = lambda v: html.escape(str(v or ""))
    label = METHOD_LABELS.get(json_file.get("method"), json_file.get("method") or "")
    when = datetime.now(ZoneInfo("America/Hermosillo")).strftime("%d/%m/%Y %H:%M")
    rows = [("Monto abonado", _money(json_file.get("amountMXN")))]
    if label:
        rows.append(("Forma de pago", label))
    if isinstance(json_file.get("balanceAfter"), (int, float)):
        rows.append(("Saldo disponible", _money(json_file["balanceAfter"])))
    rows += [("Fecha", when), ("Folio", json_file.get("entryId"))]
    table = "".join(
        f'<tr><td style="padding:8px 0;color:#6b7280">{esc(k)}</td>'
        f'<td style="padding:8px 0;text-align:right;font-weight:700">{esc(v)}</td></tr>' for k, v in rows)
    company = esc(json_file.get("companyName") or "Lavandería y Auto-Servicio")
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Abono de saldo — {company}</title></head>
<body style="margin:0;padding:16px;background:#f0f4fa;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#111827">
  <div style="max-width:480px;margin:0 auto;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 2px 10px rgba(20,20,60,.08)">
    <div style="background:linear-gradient(160deg,#1E3A8A,#2563EB 50%,#3B82F6);color:#fff;padding:22px">
      <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;opacity:.85">{company}</div>
      <div style="font-size:22px;font-weight:800;margin-top:4px">Abono de saldo</div>
    </div>
    <div style="padding:18px 22px">
      <table style="width:100%;border-collapse:collapse;font-size:15px">{table}</table>
      <div style="margin-top:16px;padding:12px;border-radius:12px;background:#eff6ff;color:#1e3a8a;font-size:13px;line-height:1.5">
        Tu saldo se usa al escanear tu código QR en la lavadora o la secadora.
      </div>
    </div>
  </div>
</body></html>"""


def _store_ticket(json_file: dict) -> str | None:
    """Upload the ticket to the 'ticketspos' container like the POS receipts.
    Random name, not the folio: the container is publicly readable, so a
    predictable name could be counted through. None when it can't be stored."""
    try:
        entry_id = int(json_file.get("entryId") or 0)
        if entry_id <= 0:
            return None
        file_name = f"topup_{datetime.utcnow():%Y%m%d}_{uuid.uuid4().hex}.html"
        result = save_receipt_html(income_id=entry_id, branch_id=int(json_file.get("companyId") or 0),
                                   html=top_up_ticket_html(json_file), file_name=file_name)
        return result.get("receiptUrl") or result.get("url")
    except Exception as e:
        print(f"[walletTopUps] ticket upload failed entry={json_file.get('entryId')}: {type(e).__name__}: {e}")
        return None


async def notify_top_up(json_file: dict) -> None:
    """Best-effort ticket to the client: push, then WhatsApp, then SMS. Runs after
    the response; a failure here never undoes or blocks the credit. One ticket
    per ledger entry (the dispatcher dedupes on sourceId).

    Like a POS sale, the ticket is an HTML page stored in ADLS and the link goes
    in the message: WhatsApp uses comprobante_listo (detail + link), SMS and push
    get "Ver su ticket: <link>". If the page can't be stored, the text-only
    abono_saldo ticket goes out instead."""
    try:
        from modules.notificationDispatch import dispatch_notification_connector  # lazy: avoids a cycle
        company_id, client_id = json_file.get("companyId"), json_file.get("clientId")
        data = {**json_file, "companyName": company_name({"companyId": company_id})}
        message = top_up_message(data)
        receipt_url = await asyncio.to_thread(_store_ticket, data)
        response = await dispatch_notification_connector({
            "companyId": company_id, "sourceType": "walletTransaction", "sourceId": json_file.get("entryId"),
            "recipientType": "client", "recipientId": client_id, "eventName": TOPUP_EVENT,
            "phone": _client_phone(client_id), "pushTitle": "Abono recibido", "messagePreview": message,
            "navigationRoute": "/my-qr",
            **({"receiptUrl": receipt_url} if receipt_url else {"waTemplate": TOPUP_TEMPLATE}),
        })
        print(f"[walletTopUps] ticket entry={json_file.get('entryId')} → HTTP {response.status_code}")
    except Exception as e:
        print(f"[walletTopUps] ticket failed entry={json_file.get('entryId')}: {e}")


def _after_credit(notify: Notify, entry: dict, json_file: dict, amount: float, method: str) -> None:
    if notify and not entry.get("replayed"):
        notify({"companyId": int(json_file["companyId"]), "clientId": int(json_file["clientId"]),
                "entryId": entry.get("entryId"), "amountMXN": amount, "method": method,
                "balanceAfter": entry.get("balanceAfter")})


def _amount(json_file: dict) -> float:
    try:
        return round(float(json_file.get("amountMXN") or 0), 2)
    except (TypeError, ValueError):
        return 0


def _evidence(row: dict) -> dict:
    return json.loads(transfer_evidence_sp({"transferEvidence": [row]}).body)


def create_pending_evidence(json_file: dict) -> dict:
    """A comprobante waiting for staff (from WhatsApp). referenceId is the clientId."""
    return _evidence({
        "action": "create", "referenceType": TOPUP_REFERENCE, "referenceId": json_file["clientId"],
        "uploadedByClientId": json_file["clientId"],
        **{k: json_file.get(k) for k in ("companyId", "claveRastreo", "transferDate", "bankFrom",
                                         "amountMXN", "evidenceFileUrl")},
    })


def confirm_transfer(json_file: dict, notify: Notify = None) -> JSONResponse:
    """Staff saw the money: credit the saldo, keep the evidence, post the entry."""
    company_id = json_file.get("companyId")
    client_id = json_file.get("clientId")
    clave = str(json_file.get("claveRastreo") or "").strip().upper()
    bank = str(json_file.get("bankFrom") or "").strip()
    date = json_file.get("transferDate")
    evidence_id = json_file.get("transferEvidenceId")
    try:
        amount = round(float(json_file.get("amountMXN") or 0), 2)
    except (TypeError, ValueError):
        amount = 0
    if not company_id or not client_id or amount <= 0 or len(clave) < 6 or not bank or not date:
        return JSONResponse({"error": "Faltan datos de la transferencia."}, status_code=400)
    if not evidence_id and not json_file.get("evidenceFileUrl"):
        return JSONResponse({"error": "El comprobante es obligatorio."}, status_code=400)

    entry = post_entry(
        company_id=int(company_id), client_id=int(client_id), entry_type="DEPOSIT", direction="C",
        amount_mxn=amount, idempotency_key=f"transfer:{company_id}:{clave}",
        reference_type="transfer", note=f"Transferencia {bank} {date}, clave {clave}"[:255],
    )
    if entry.get("error"):
        return JSONResponse({"error": entry["error"]}, status_code=400)
    if entry.get("replayed"):
        return JSONResponse({"replayed": True, "balanceAfter": entry.get("balanceAfter")}, status_code=200)

    if evidence_id:
        evidence = _evidence({"action": "validate", "companyId": company_id, "transferEvidenceId": evidence_id,
                              "validationStatus": "VALID", "aiReasoning": "Confirmada por personal en el POS"})
    else:
        evidence = create_pending_evidence({
            "companyId": company_id, "clientId": client_id, "claveRastreo": clave, "transferDate": date,
            "bankFrom": bank, "amountMXN": amount, "evidenceFileUrl": json_file.get("evidenceFileUrl"),
        })
        if not evidence.get("error"):
            evidence = _evidence({"action": "validate", "companyId": company_id,
                                  "transferEvidenceId": evidence.get("transferEvidenceId"),
                                  "validationStatus": "VALID", "aiReasoning": "Confirmada por personal en el POS"})

    posted = post_wallet_topup_journal_entry(int(company_id), entry.get("entryId"), amount, date, "transferencia")
    log_workflow_step("Transfer Top-up Confirmed", workflow_name="money_trail", action="wallet_topup",
                      entity="walletTransactions", entity_id=entry.get("entryId"),
                      message=f"${amount:,.2f} MXN journal={posted}")
    log_audit("WalletTopUp", entry.get("entryId"), "confirmedByUserId", None, json_file.get("userId"), action="INSERT")
    _after_credit(notify, entry, json_file, amount, "transferencia")
    return JSONResponse({
        "balanceAfter": entry.get("balanceAfter"), "replayed": False,
        "evidenceSaved": not evidence.get("error"), "journalPosted": posted,
    }, status_code=200)


def _credit_in_person(json_file: dict, notify: Notify, method: str, key: str, note: str,
                      reference_type: str = None, reference_id=None) -> JSONResponse:
    amount = _amount(json_file)
    entry = post_entry(
        company_id=int(json_file["companyId"]), client_id=int(json_file["clientId"]), entry_type="DEPOSIT",
        direction="C", amount_mxn=amount, idempotency_key=key, reference_type=reference_type,
        reference_id=reference_id, note=note[:255],
    )
    if entry.get("error"):
        return JSONResponse({"error": entry["error"]}, status_code=400)
    if not entry.get("replayed"):
        log_workflow_step(f"{method.capitalize()} Top-up Credited", workflow_name="money_trail", action="wallet_topup",
                          entity="walletTransactions", entity_id=entry.get("entryId"), message=f"${amount:,.2f} MXN")
        log_audit("WalletTopUp", entry.get("entryId"), "confirmedByUserId", None, json_file.get("userId"),
                  action="INSERT")
    _after_credit(notify, entry, json_file, amount, method)
    return JSONResponse({"balanceAfter": entry.get("balanceAfter"), "replayed": bool(entry.get("replayed"))},
                        status_code=200)


def credit_cash(json_file: dict, notify: Notify = None) -> JSONResponse:
    """Cash at the register. The app makes one key per attempt, so a double tap
    or a retry credits once."""
    company_id, client_id = json_file.get("companyId"), json_file.get("clientId")
    key = str(json_file.get("idempotencyKey") or "")
    if not company_id or not client_id or _amount(json_file) <= 0:
        return JSONResponse({"error": "Faltan datos del abono."}, status_code=400)
    if not key.startswith(f"cash:{company_id}:") or len(key) > 64:
        return JSONResponse({"error": "Llave del abono inválida."}, status_code=400)
    return _credit_in_person(json_file, notify, "efectivo", key,
                             f"Recarga en efectivo en caja (usuario {json_file.get('userId')})")


def credit_terminal(json_file: dict, notify: Notify = None) -> JSONResponse:
    """Charged on the company's physical terminal (RFC-012, phase 0). Terminal +
    operation number is the key: one operation never credits twice, nor another client."""
    company_id, client_id, terminal_id = (json_file.get(k) for k in ("companyId", "clientId", "terminalId"))
    operation = str(json_file.get("operationNumber") or "").strip().upper()
    if not company_id or not client_id or not terminal_id or _amount(json_file) <= 0:
        return JSONResponse({"error": "Faltan datos del abono."}, status_code=400)
    if not OPERATION_PATTERN.match(operation):
        return JSONResponse({"error": "Número de operación inválido."}, status_code=400)
    name = str(json_file.get("terminalName") or "terminal")
    return _credit_in_person(json_file, notify, "terminal", f"terminal:{terminal_id}:{operation}",
                             f"Recarga con {name}, operación {operation} (usuario {json_file.get('userId')})",
                             reference_type="commissionTerminal", reference_id=int(terminal_id))


def reject_evidence(json_file: dict) -> JSONResponse:
    result = _evidence({"action": "validate", "companyId": json_file.get("companyId"),
                        "transferEvidenceId": json_file.get("transferEvidenceId"), "validationStatus": "INVALID",
                        "aiReasoning": "Rechazada por personal en el POS"})
    if result.get("error"):
        return JSONResponse(result, status_code=400)
    log_audit("WalletTopUp", json_file.get("transferEvidenceId"), "evidenceRejectedByUserId", None,
              json_file.get("userId"), action="UPDATE")
    return JSONResponse({"rejected": True}, status_code=200)
