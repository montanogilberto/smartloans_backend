"""
Saldo top-ups a person confirmed. The evidence (comprobante) only proves a claim:
money is credited when a staff member says they saw it in the company's account.
Crediting, keeping the evidence and posting the accounting entry happen here so
none of the three is left to the app.
"""
import json
import re
from typing import Callable, Optional
from fastapi.responses import JSONResponse
from databases import connection
from modules.companies import company_name
from modules.journalEntries import post_wallet_topup_journal_entry
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


async def notify_top_up(json_file: dict) -> None:
    """Best-effort ticket to the client: push, then WhatsApp, then SMS. Runs after
    the response; a failure here never undoes or blocks the credit. One ticket
    per ledger entry (the dispatcher dedupes on sourceId)."""
    try:
        from modules.notificationDispatch import dispatch_notification_connector  # lazy: avoids a cycle
        company_id, client_id = json_file.get("companyId"), json_file.get("clientId")
        message = top_up_message({**json_file, "companyName": company_name({"companyId": company_id})})
        response = await dispatch_notification_connector({
            "companyId": company_id, "sourceType": "walletTransaction", "sourceId": json_file.get("entryId"),
            "recipientType": "client", "recipientId": client_id, "eventName": TOPUP_EVENT,
            "phone": _client_phone(client_id), "pushTitle": "Abono recibido", "messagePreview": message,
            "waTemplate": TOPUP_TEMPLATE, "navigationRoute": "/my-qr",
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
