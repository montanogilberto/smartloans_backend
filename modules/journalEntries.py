"""
Journal entries (Asientos Contables) — double-entry ledger. Every
row here is INSERT-only (a "post"); corrections are a new reversing
entry, never an edit or delete. Módulo Contabilidad.

Spec: posgmo-factory/tests/prd_journalEntry.json

Libro Mayor, Balanza de Comprobación, Estado de Resultados, Balance
General and Flujo de Efectivo are NOT separate tables — they are read
projections over journalEntryLines + chartOfAccounts (see
sp_journalEntries_ledger / sp_journalEntries_trialBalance in
sql/sp_journalEntries.sql). Only the ledger and trial-balance
projections are wired here; full income-statement/balance-sheet/
cash-flow reports need their own later reporting PRD.
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


def journal_entries_sp(json_file: dict):
    """CRUD passthrough (sp_journalEntries). action 1=post (with nested
    lines[]), 2=void (POSTED->VOID only), 3=always rejected."""
    try:
        result = _sp("sp_journalEntries", json_file)
        status_code = 400 if isinstance(result, dict) and result.get("error") else 200
        return JSONResponse(result, status_code=status_code)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def all_journal_entries_sp(json_file: dict):
    """Libro Diario: header list, filterable by fromDate/toDate/referenceType/status."""
    try:
        return JSONResponse(_sp("sp_journalEntries_all", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def one_journal_entry_sp(json_file: dict):
    """Detalle del asiento (header + lines) — el drill-down Movimiento -> Asiento."""
    try:
        return JSONResponse(_sp("sp_journalEntries_one", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def journal_entries_ledger_sp(json_file: dict):
    """GET /journalEntries/ledger — Libro Mayor projection (movements + running balance per account)."""
    try:
        return JSONResponse(_sp("sp_journalEntries_ledger", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def journal_entries_trial_balance_sp(json_file: dict):
    """GET /journalEntries/trial-balance — Balanza de Comprobación projection.

    sp_journalEntries_trialBalance returns accountsJson as a JSON-encoded
    *string* column (it's built from a T-SQL variable, not an inline FOR
    JSON subquery, so SQL Server doesn't auto-nest it) — decode it here so
    the API returns real nested JSON instead of an escaped string.
    """
    try:
        result = _sp("sp_journalEntries_trialBalance", json_file)
        if isinstance(result, dict) and isinstance(result.get("accountsJson"), str):
            result["accounts"] = json.loads(result.pop("accountsJson"))
            result["balanced"] = bool(result.get("balanced"))
        return JSONResponse(result, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
