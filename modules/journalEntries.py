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
from datetime import datetime
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


# ── Auto-posting: income/expenses -> journalEntry ───────────────────────────
# Best-effort bridge called from modules/income.py and modules/expenses.py
# right after a successful INSERT. The account mapping is intentionally the
# simplest one that keeps every asiento balanced: everything routes through
# "Bancos" — there is no per-category (Nómina/Servicios/supplier type) split
# yet. Never raises: the income/expense row already committed, so a missing
# chart of accounts or a posting error must not break that response — it's
# only logged. See sql/sp_journalEntries.sql hints + prd_journalEntry.json.

DEFAULT_BANK_ACCOUNT_CODE = '1105'      # Bancos (ASSET)
DEFAULT_INCOME_ACCOUNT_CODE = '4105'    # Ingresos por ventas (INCOME)
DEFAULT_EXPENSE_ACCOUNT_CODE = '5105'   # Gastos de operación (EXPENSE)


def _normalize_entry_date(raw) -> str:
    if raw:
        return str(raw)[:10]
    return datetime.utcnow().strftime('%Y-%m-%d')


def _get_account_id(company_id: int, code: str):
    """Looks up an active chartOfAccounts.accountId by code for a company.
    Returns None (never raises) if the catalog is missing/incomplete —
    callers treat that as "skip the auto-post"."""
    try:
        result = _sp("sp_chartOfAccounts_all", {"chartOfAccounts": [{"companyId": company_id}]})
        accounts = result.get("chartOfAccounts", []) if isinstance(result, dict) else []
        for account in accounts:
            if account.get("code") == code and account.get("isActive"):
                return account.get("accountId")
    except Exception as e:
        print(f"[journalEntries] _get_account_id failed companyId={company_id} code={code}: {e}")
    return None


def _post_movement_journal_entry(company_id: int, reference_type: str, reference_id: int,
                                  amount: float, entry_date, description: str,
                                  debit_code: str, credit_code: str):
    if not company_id or not amount or amount <= 0:
        return
    try:
        debit_account_id = _get_account_id(company_id, debit_code)
        credit_account_id = _get_account_id(company_id, credit_code)
        if not debit_account_id or not credit_account_id:
            print(f"[journalEntries] skip auto-post for {reference_type} {reference_id}: "
                  f"missing account {debit_code}/{credit_code} for companyId={company_id} "
                  f"(sp_chartOfAccounts_seed may not have run for this company)")
            return

        payload = {"journalEntries": [{
            "action": 1,
            "companyId": company_id,
            "entryDate": _normalize_entry_date(entry_date),
            "description": description,
            "referenceType": reference_type,
            "referenceId": reference_id,
            "lines": [
                {"accountId": debit_account_id, "debit": amount, "credit": 0},
                {"accountId": credit_account_id, "debit": 0, "credit": amount},
            ],
        }]}
        result = _sp("sp_journalEntries", payload)
        if isinstance(result, dict) and result.get("error"):
            print(f"[journalEntries] auto-post FAILED for {reference_type} {reference_id}: {result['error']}")
        else:
            print(f"[journalEntries] auto-posted asiento for {reference_type} {reference_id}")
    except Exception as e:
        print(f"[journalEntries] auto-post EXCEPTION for {reference_type} {reference_id}: {e}")


def post_income_journal_entry(company_id: int, income_id: int, amount: float, entry_date=None):
    """Debe Bancos / Haber Ingresos por ventas. Called from modules/income.py
    after a successful sp_income action=1."""
    _post_movement_journal_entry(
        company_id, 'income', income_id, amount, entry_date,
        description=f"Ingreso #{income_id}",
        debit_code=DEFAULT_BANK_ACCOUNT_CODE, credit_code=DEFAULT_INCOME_ACCOUNT_CODE,
    )


def post_expense_journal_entry(company_id: int, expense_id: int, amount: float, entry_date=None):
    """Debe Gastos de operación / Haber Bancos. Called from modules/expenses.py
    after a successful sp_expense action=1 (any expenseType)."""
    _post_movement_journal_entry(
        company_id, 'expense', expense_id, amount, entry_date,
        description=f"Egreso #{expense_id}",
        debit_code=DEFAULT_EXPENSE_ACCOUNT_CODE, credit_code=DEFAULT_BANK_ACCOUNT_CODE,
    )


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
