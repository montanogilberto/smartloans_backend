"""
Saldo top-ups a person confirmed. The evidence (comprobante) only proves a claim:
money is credited when a staff member says they saw it in the company's account.
Crediting, keeping the evidence and posting the accounting entry happen here so
none of the three is left to the app.
"""
import json
from fastapi.responses import JSONResponse
from modules.journalEntries import post_wallet_topup_journal_entry
from modules.transferEvidence import transfer_evidence_sp
from modules.walletTransactions import post_entry
from observability.logger import log_audit, log_workflow_step

TOPUP_REFERENCE = "WALLET_TOPUP"


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


def confirm_transfer(json_file: dict) -> JSONResponse:
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
    return JSONResponse({
        "balanceAfter": entry.get("balanceAfter"), "replayed": False,
        "evidenceSaved": not evidence.get("error"), "journalPosted": posted,
    }, status_code=200)


def reject_evidence(json_file: dict) -> JSONResponse:
    result = _evidence({"action": "validate", "companyId": json_file.get("companyId"),
                        "transferEvidenceId": json_file.get("transferEvidenceId"), "validationStatus": "INVALID",
                        "aiReasoning": "Rechazada por personal en el POS"})
    if result.get("error"):
        return JSONResponse(result, status_code=400)
    log_audit("WalletTopUp", json_file.get("transferEvidenceId"), "evidenceRejectedByUserId", None,
              json_file.get("userId"), action="UPDATE")
    return JSONResponse({"rejected": True}, status_code=200)
