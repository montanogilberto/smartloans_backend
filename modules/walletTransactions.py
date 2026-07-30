"""
walletTransactions — the INSERT-only money ledger. Banking-first Phase 1.

Spec: posgmo-factory/tests/prd_walletTransaction.json. Balances are projections
over this ledger (sp_walletTransactions_balance); the SP enforces INSERT-only,
per-wallet serialization, no-overdraft and idempotent replays — this module is
a thin caller plus the ledger API other modules (transfers orchestrator) use.
"""

import json
from fastapi.responses import JSONResponse
from databases import connection


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


def post_entry(*, company_id: int, client_id, entry_type: str, direction: str,
               amount_mxn: float, idempotency_key: str, reference_type: str = None,
               reference_id: int = None, note: str = None) -> dict:
    """Internal ledger API used by orchestrators. Returns the SP result dict:
    the created entry, the original entry (replayed=true), or {error}."""
    result = _sp("sp_walletTransactions", {"walletTransactions": [{
        "action": 1, "companyId": company_id, "clientId": client_id,
        "entryType": entry_type, "direction": direction, "amountMXN": amount_mxn,
        "referenceType": reference_type, "referenceId": reference_id,
        "idempotencyKey": idempotency_key, "note": note,
    }]})
    tag = "REPLAY" if result.get("replayed") else ("ERROR " + result["error"] if result.get("error") else f"balance={result.get('balanceAfter')}")
    print(f"[ledger] {entry_type} {direction} {amount_mxn} MXN clientId={client_id} key={idempotency_key} → {tag}")
    return result


def get_balance(company_id: int, client_id) -> dict:
    """{ availableBalance, reservedBalance } for a client (or the platform when
    client_id is None)."""
    return _sp("sp_walletTransactions_balance", {"walletTransactions": [{
        "companyId": company_id, "clientId": client_id,
    }]})


# ── Route handlers ──────────────────────────────────────────────────────────

def wallet_transactions_sp(json_file: dict):
    """POST /walletTransactions — action 1 insert only (the SP rejects 2/3)."""
    try:
        return JSONResponse(_sp("sp_walletTransactions", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def all_wallet_transactions_sp(json_file: dict):
    """POST /all_walletTransactions — movement statement, newest first."""
    try:
        return JSONResponse(_sp("sp_walletTransactions_all", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


async def ledger_balance(payload: dict):
    """POST /ledger/balance — { clientId?, companyId } → balances projection."""
    company_id = payload.get("companyId")
    if not company_id:
        return JSONResponse({"error": "companyId es requerido"}, status_code=400)
    try:
        result = get_balance(company_id, payload.get("clientId"))
        return JSONResponse(result, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
