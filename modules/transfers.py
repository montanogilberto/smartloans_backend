"""
Transfers — outbound SPEI dispersión + the Phase-1 payment orchestrator.

Spec: posgmo-factory/tests/prd_transfer.json and
docs/payment-banking-first-redesign.md §5/§9. The orchestrator sequence is
ledger-first and idempotent end to end:

    1. replay check (transfers.idempotencyKey)
    2. resolve destination = the recipient's DEFAULT VERIFIED bank account
    3. ledger DEBIT on the funding wallet   (key ":debit")   — no overdraft
    4. create the transfer row (pending)
    5. STP send_spei (mock mode until the STP contract exists)
    6. success → transfer settled + CEP  |  failure → ledger REVERSAL (":reversal")

A failed provider call can never strand money: the debit is reversed and the
transfer row records the failure for audit.
"""

import json
from fastapi.responses import JSONResponse
from databases import connection

from modules.stpProvider import send_spei
from modules.walletTransactions import post_entry, get_balance
from observability.logger import log_workflow_step
from observability.integrations import timed_integration


def _conn():
    return connection()


def _sp(proc: str, json_file: dict):
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{proc}] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


def _default_verified_account(company_id: int, client_id: int):
    """The recipient's default verified bank account, with the FULL clabe (via
    the internal _one SP) — used only to address the SPEI, never returned."""
    accounts = _sp("sp_bankAccounts_all", {"bankAccounts": [{
        "companyId": company_id, "clientId": client_id,
    }]}).get("bankAccounts", [])
    chosen = next((a for a in accounts if a.get("isVerified") and a.get("isDefault")), None) \
        or next((a for a in accounts if a.get("isVerified")), None)
    if not chosen:
        return None
    return _sp("sp_bankAccounts_one", {"bankAccounts": [{
        "bankAccountId": chosen["bankAccountId"],
    }]})


# ── Orchestrator ────────────────────────────────────────────────────────────

async def disburse_payment(payload: dict):
    """POST /payments/disburse — SPEI money out of a wallet to a bank account.

    Body (doc §9): { companyId, lenderId, borrowerId?, amountMXN, purpose?,
                     loanId?, idempotencyKey }
      purpose loan_disbursement (default): lender wallet → borrower's bank.
      purpose lender_payout / refund:      own wallet    → own bank.
    """
    company_id = payload.get("companyId")
    purpose    = payload.get("purpose", "loan_disbursement")
    amount     = float(payload.get("amountMXN") or payload.get("amount") or 0)
    loan_id    = payload.get("loanId")
    idem_key   = payload.get("idempotencyKey")

    if purpose == "loan_disbursement":
        from_client = payload.get("lenderId")
        to_client   = payload.get("borrowerId")
        entry_type  = "LOAN_FUNDING"
    else:  # lender_payout | refund — money leaves the owner's own wallet
        from_client = payload.get("lenderId") or payload.get("clientId")
        to_client   = from_client
        entry_type  = "WITHDRAWAL"

    if not company_id or not from_client or not to_client or amount <= 0 or not idem_key:
        return JSONResponse({"error": "companyId, lenderId/clientId, amountMXN > 0 e idempotencyKey son requeridos"}, status_code=400)

    print(f"[transfers] disburse START purpose={purpose} from={from_client} to={to_client} "
          f"amount={amount} key={idem_key}")

    # 1. Replay?
    existing = _sp("sp_transfers_one", {"transfers": [{"companyId": company_id, "idempotencyKey": idem_key}]})
    if existing.get("transferId"):
        print(f"[transfers] disburse REPLAY key={idem_key} → transferId={existing['transferId']} ({existing.get('status')})")
        return JSONResponse({**existing, "replayed": True}, status_code=200)

    # 2. Destination account (default verified, full CLABE for the rail only).
    dest = _default_verified_account(company_id, to_client)
    if not dest:
        return JSONResponse({"error": "El destinatario no tiene una cuenta bancaria verificada."}, status_code=400)

    # 3. Ledger debit — the SP guards overdraft and serializes per wallet.
    debit = post_entry(company_id=company_id, client_id=from_client, entry_type=entry_type,
                       direction="D", amount_mxn=amount, idempotency_key=f"{idem_key}:debit",
                       reference_type="transfer", note=f"{purpose} → clientId {to_client}")
    if debit.get("error"):
        return JSONResponse({"error": debit["error"]}, status_code=400)

    # 4. Transfer row (pending).
    transfer = _sp("sp_transfers", {"transfers": [{
        "action": 1, "companyId": company_id, "toClientId": to_client,
        "toBankAccountId": dest["bankAccountId"], "amountMXN": amount,
        "purpose": purpose, "loanId": loan_id, "provider": "stp",
        "idempotencyKey": idem_key,
    }]})
    if transfer.get("error"):
        post_entry(company_id=company_id, client_id=from_client, entry_type="REVERSAL",
                   direction="C", amount_mxn=amount, idempotency_key=f"{idem_key}:reversal",
                   reference_type="transfer", note="reversa: fallo creando transfer")
        return JSONResponse({"error": transfer["error"]}, status_code=500)
    transfer_id = transfer["transferId"]

    # 5. The rail — cada llamada al proveedor queda en integrationLogs.
    with timed_integration("stp", "send_spei",
                           request={"amountMXN": amount, "purpose": purpose, "transferId": transfer_id}) as span:
        result = send_spei(clabe_destino=dest["clabe"], nombre_beneficiario=dest["holderName"],
                           amount_mxn=amount, concepto=f"SmartLoans {purpose}"[:40], reference=idem_key)
        span.response = {"ok": result.get("ok"), "status": result.get("status"),
                         "providerRef": result.get("providerRef"), "mock": result.get("mock")}

    # 6. Settle or reverse.
    if result.get("ok"):
        updated = _sp("sp_transfers", {"transfers": [{
            "action": 2, "transferId": transfer_id, "companyId": company_id,
            "status": result["status"], "providerRef": result.get("providerRef"),
            "cepUrl": result.get("cepUrl"),
        }]})
        log_workflow_step("SPEI Sent", workflow_name="money_trail", action=purpose,
                          entity="transfers", entity_id=transfer_id,
                          message=f"${amount:,.2f} MXN → clientId {to_client}"
                                  + (" (MOCK — sin dinero real)" if result.get("mock") else ""))
        print(f"[transfers] disburse SUCCESS transferId={transfer_id} status={result['status']} "
              f"providerRef={result.get('providerRef')}")
        return JSONResponse({**updated, "mock": result.get("mock", False)}, status_code=200)

    post_entry(company_id=company_id, client_id=from_client, entry_type="REVERSAL",
               direction="C", amount_mxn=amount, idempotency_key=f"{idem_key}:reversal",
               reference_type="transfer", reference_id=transfer_id,
               note="reversa: SPEI rechazado")
    failed = _sp("sp_transfers", {"transfers": [{
        "action": 2, "transferId": transfer_id, "companyId": company_id,
        "status": "failed", "failureReason": result.get("error", "provider error"),
    }]})
    log_workflow_step("SPEI Failed — ledger reversed", workflow_name="money_trail", action=purpose,
                      status="FAILED", entity="transfers", entity_id=transfer_id,
                      message=f"${amount:,.2f} MXN → clientId {to_client}: {result.get('error')}")
    print(f"[transfers] disburse FAILED transferId={transfer_id}: {result.get('error')} — ledger reversed")
    return JSONResponse({"error": result.get("error", "No se pudo enviar la transferencia."), **failed}, status_code=400)


async def payment_status(payload: dict):
    """POST /payments/status — { companyId, transferId | idempotencyKey }."""
    result = _sp("sp_transfers_one", {"transfers": [{
        "companyId": payload.get("companyId"),
        "transferId": payload.get("transferId"),
        "idempotencyKey": payload.get("idempotencyKey"),
    }]})
    if not result:
        return JSONResponse({"error": "Transferencia no encontrada"}, status_code=404)
    return JSONResponse(result, status_code=200)


# ── CRUD reads ──────────────────────────────────────────────────────────────

def all_transfers_sp(json_file: dict):
    try:
        return JSONResponse(_sp("sp_transfers_all", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def one_transfer_sp(json_file: dict):
    try:
        return JSONResponse(_sp("sp_transfers_one", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
