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
from datetime import datetime, timedelta, timezone
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
# right after a successful INSERT. Never raises: the income/expense row
# already committed, so a missing chart of accounts or a posting error must
# not break that response — it's only logged. Duplicates are rejected by
# sp_journalEntries itself (one POSTED entry per companyId + referenceType +
# referenceId), so a retried hook can't double-post.
#
# Posting map (POSVending/docs/accounting-module.md §7.3, Step 3, 2026-10-01):
#   income   Efectivo              Dr 1101 Caja    / Cr 4105 Ventas
#   income   Tarjeta/Transferencia Dr 1105 Bancos  / Cr 4105 Ventas
#   expense  Dr by type (payroll 5110, general/servicios 5115, inventory 5105)
#            Cr 1101 Caja (Efectivo) or 1105 Bancos (any other method)
# Owner decisions: inventory is expensed (5105, no 1115); payroll is
# cash-basis (no 2110 accrual); IVA is not split out.

CASH_ACCOUNT_CODE = '1101'              # Caja (ASSET)
DEFAULT_BANK_ACCOUNT_CODE = '1105'      # Bancos (ASSET)
DEFAULT_INCOME_ACCOUNT_CODE = '4105'    # Ingresos por ventas (INCOME)
DEFAULT_EXPENSE_ACCOUNT_CODE = '5105'   # Gastos de operación (EXPENSE)
COMMISSION_EXPENSE_ACCOUNT_CODE = '5120'  # Comisiones bancarias (EXPENSE)

EXPENSE_ACCOUNT_BY_TYPE = {
    'payroll': '5110',     # Nómina
    'general': '5115',     # Servicios (the form's "Servicios" tab sends 'general')
    'inventory': '5105',   # Gastos de operación — inventory is expensed (Q2)
}

_CASH_METHODS = {'efectivo', 'cash'}
_BANK_METHODS = {'tarjeta', 'terminal', 'transferencia', 'transferir', 'transfer', 'spei', 'card'}


def cash_or_bank_code(payment_method) -> str:
    """Asset account a movement settles through: Efectivo → 1101 Caja,
    card/transfer → 1105 Bancos. An unknown method keeps the pre-2026-10-01
    behavior (Bancos) and is logged so reconciliation can catch it."""
    method = str(payment_method or '').strip().lower()
    if method in _CASH_METHODS:
        return CASH_ACCOUNT_CODE
    if method not in _BANK_METHODS:
        print(f"[journalEntries] unknown paymentMethod {payment_method!r} -> posting to Bancos {DEFAULT_BANK_ACCOUNT_CODE}")
    return DEFAULT_BANK_ACCOUNT_CODE


def expense_account_code(expense_type) -> str:
    """Debit account for an expense by expenseType (sp_expense defaults a
    missing type to 'inventory', so None maps the same way)."""
    return EXPENSE_ACCOUNT_BY_TYPE.get(str(expense_type or 'inventory').strip().lower(),
                                       DEFAULT_EXPENSE_ACCOUNT_CODE)


HERMOSILLO_OFFSET = timedelta(hours=-7)   # UTC-7, no DST


def _normalize_entry_date(raw) -> str:
    """Hermosillo business date ('YYYY-MM-DD') for a movement.

    - 'YYYY-MM-DD'                      → kept as is (already a local day).
    - timestamp WITH a zone ('…Z', '…-07:00', '…+00:00') → converted to
      Hermosillo time, then its date. The POS cart sends
      new Date().toISOString(); taking its first 10 chars dated every sale
      after 17:00 local on the NEXT day (and month-end evenings in the next
      month) — fixed 2026-10-01.
    - timestamp WITHOUT a zone          → first 10 chars (unknown zone; legacy).
    - empty                             → today in Hermosillo.
    """
    if not raw:
        return (datetime.now(timezone.utc) + HERMOSILLO_OFFSET).strftime('%Y-%m-%d')
    text = str(raw).strip()
    has_zone = text.endswith('Z') or (len(text) > 19 and text[-6] in '+-' and text[-3] == ':')
    if 'T' in text and has_zone:
        try:
            moment = datetime.fromisoformat(text.replace('Z', '+00:00'))
            return (moment.astimezone(timezone.utc) + HERMOSILLO_OFFSET).strftime('%Y-%m-%d')
        except ValueError:
            pass
    return text[:10]


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
                                  debit_code: str, credit_code: str) -> bool:
    """Best-effort post of a 2-line entry. Returns True only if an entry was
    actually posted, so a caller that VOIDed a predecessor can tell."""
    if not company_id or not amount or amount <= 0:
        return False
    try:
        debit_account_id = _get_account_id(company_id, debit_code)
        credit_account_id = _get_account_id(company_id, credit_code)
        if not debit_account_id or not credit_account_id:
            print(f"[journalEntries] skip auto-post for {reference_type} {reference_id}: "
                  f"missing account {debit_code}/{credit_code} for companyId={company_id} "
                  f"(sp_chartOfAccounts_seed may not have run for this company)")
            return False

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
            return False
        print(f"[journalEntries] auto-posted asiento for {reference_type} {reference_id}")
        return True
    except Exception as e:
        print(f"[journalEntries] auto-post EXCEPTION for {reference_type} {reference_id}: {e}")
        return False


def post_income_journal_entry(company_id: int, income_id: int, amount: float, entry_date=None,
                              payment_method=None):
    """Debe Caja (Efectivo) or Bancos / Haber Ingresos por ventas. Called from
    modules/income.py after a successful sp_income action=1."""
    _post_movement_journal_entry(
        company_id, 'income', income_id, amount, entry_date,
        description=f"Ingreso #{income_id}",
        debit_code=cash_or_bank_code(payment_method), credit_code=DEFAULT_INCOME_ACCOUNT_CODE,
    )


def post_expense_journal_entry(company_id: int, expense_id: int, amount: float, entry_date=None,
                               payment_method=None, expense_type=None):
    """Debe gasto by expenseType / Haber Caja (Efectivo) or Bancos. Called from
    modules/expenses.py after a successful sp_expense action=1."""
    _post_movement_journal_entry(
        company_id, 'expense', expense_id, amount, entry_date,
        description=f"Egreso #{expense_id}",
        debit_code=expense_account_code(expense_type), credit_code=cash_or_bank_code(payment_method),
    )


# ── Expense edit / delete -> ledger ─────────────────────────────────────────
# sp_expense action 2 (update) overwrites the row in place and action 3
# (delete) removes it, but the POSTED entry written on insert used to stay
# as-is, so the books drifted from the expenses table. Journal entries are
# immutable (only POSTED -> VOID), so a correction is VOID + a fresh post —
# the same shape as sp_journalEntries_correctDates. Both helpers only ever
# touch entries that already exist: they never create an entry for an expense
# that has none (historic expenses are the backfill's business, see
# accounting-module.md Q1), and they are idempotent, so a retried hook is safe.

def _fetch_expense(expense_id: int):
    """Current expenses row as a dict, or None if it no longer exists
    (sp_expense_one)."""
    row = _sp("sp_expense_one", {"expenses": [{"expenseId": int(expense_id)}]})
    if isinstance(row, dict) and row.get("error"):
        raise RuntimeError(f"sp_expense_one: {row['error']}")
    if not row:
        return None
    return {"companyId": row.get("companyId"), "total": row.get("total"),
            "paymentMethod": row.get("paymentMethod"), "expenseType": row.get("expenseType")}


def _fetch_posted_expense_entries(expense_id: int) -> list:
    """POSTED journal entries for this expense (any company), with the account
    codes they debit/credit, as the 2-line entries the auto-post writes
    (sp_journalEntries_byReference)."""
    entries = _sp("sp_journalEntries_byReference", {"journalEntries": [
        {"referenceType": "expense", "referenceId": int(expense_id), "status": "POSTED"}]})
    if isinstance(entries, dict):
        if entries.get("error"):
            raise RuntimeError(f"sp_journalEntries_byReference: {entries['error']}")
        return []
    return [
        {"entryId": e.get("entryId"), "companyId": e.get("companyId"), "entryDate": e.get("entryDate"),
         "amount": float(e.get("amount") or 0), "debitCode": e.get("debitCode"), "creditCode": e.get("creditCode")}
        for e in entries
    ]


def _void_entry(entry_id: int, company_id: int) -> None:
    result = _sp("sp_journalEntries", {"journalEntries": [
        {"action": 2, "entryId": entry_id, "companyId": company_id, "status": "VOID"}]})
    if isinstance(result, dict) and result.get("error"):
        raise RuntimeError(result["error"])


def void_expense_journal_entries(expense_id: int) -> dict:
    """A deleted expense must stop counting in the books: VOID its POSTED entries."""
    voided = []
    for entry in _fetch_posted_expense_entries(expense_id):
        _void_entry(entry["entryId"], entry["companyId"])
        voided.append(entry["entryId"])
    return {"status": "voided" if voided else "no_entry", "voided": voided}


def resync_expense_journal_entry(expense_id: int, new_entry_date=None) -> dict:
    """After an expense update, make its POSTED entry match the row.

    Compares the entry against what the row implies today (amount, expense
    account by expenseType, Caja/Bancos by paymentMethod, company). Equal ->
    no-op (so a receiptUrl-only update, or a payload that repeats old values,
    leaves the books alone). Different -> VOID + re-post. `new_entry_date` is
    the already-normalized business date, passed only when the update payload
    itself carried a paymentDate; otherwise the entry keeps its date.
    """
    expense = _fetch_expense(expense_id)
    if expense is None:
        return void_expense_journal_entries(expense_id)

    posted = _fetch_posted_expense_entries(expense_id)
    if not posted:
        return {"status": "no_entry", "voided": []}

    company_id = expense["companyId"]
    amount = round(float(expense["total"] or 0), 2)
    debit_code = expense_account_code(expense["expenseType"])
    credit_code = cash_or_bank_code(expense["paymentMethod"])
    entry_date = new_entry_date or posted[0]["entryDate"]

    if (len(posted) == 1 and posted[0]["companyId"] == company_id
            and abs(posted[0]["amount"] - amount) < 0.005
            and posted[0]["debitCode"] == debit_code and posted[0]["creditCode"] == credit_code
            and posted[0]["entryDate"] == entry_date):
        return {"status": "unchanged", "voided": []}

    # Never VOID what we cannot replace: a missing account would leave the
    # expense with no entry at all, which is worse than a stale one.
    if amount > 0 and (not _get_account_id(company_id, debit_code)
                       or not _get_account_id(company_id, credit_code)):
        print(f"[journalEntries] expense {expense_id} changed but accounts {debit_code}/{credit_code} "
              f"are missing for companyId={company_id}: leaving the old entry")
        return {"status": "skipped_missing_accounts", "voided": []}

    voided = []
    for entry in posted:
        _void_entry(entry["entryId"], entry["companyId"])
        voided.append(entry["entryId"])

    if amount <= 0:
        return {"status": "voided", "voided": voided}
    reposted = _post_movement_journal_entry(
        company_id, 'expense', expense_id, amount, entry_date,
        description=f"Egreso #{expense_id}", debit_code=debit_code, credit_code=credit_code,
    )
    return {"status": "reposted" if reposted else "voided_repost_failed", "voided": voided}


def post_income_commission_journal_entry(company_id: int, income_id: int, commission_amount, entry_date=None):
    """Debe 5120 Comisiones bancarias / Haber 1105 Bancos for the card-terminal
    commission stamped on a sale (sp_income_applyCommission). Step 4,
    2026-10-01. referenceType 'income_commission' + referenceId incomeId;
    sp_journalEntries rejects a second POSTED one, so retries are safe.
    entry_date must be the SAME value the sale's own entry used, so both land
    on the same Hermosillo day."""
    try:
        amount = round(float(commission_amount or 0), 2)
    except (TypeError, ValueError):
        amount = 0
    _post_movement_journal_entry(
        company_id, 'income_commission', income_id, amount, entry_date,
        description=f"Comisión terminal ingreso #{income_id}",
        debit_code=COMMISSION_EXPENSE_ACCOUNT_CODE, credit_code=DEFAULT_BANK_ACCOUNT_CODE,
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


def journal_entries_balance_sheet_sp(json_file: dict):
    """POST /journalEntries/balance-sheet — Balance General / Estado de Situación
    Financiera (read projection over the journal; Step 8, 2026-10-01).

    sp_journalEntries_balanceSheet returns the finished JSON document as a
    string column ([jsonResult]); _sp concatenates the chunks and parses it.
    All accounting math happens in SQL (fn_journalEntries_balanceSheet) — this
    layer never computes balances. 400 on bad input ({"error": ...}).
    """
    try:
        result = _sp("sp_journalEntries_balanceSheet", json_file)
        status_code = 400 if isinstance(result, dict) and result.get("error") else 200
        return JSONResponse(result, status_code=status_code)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
