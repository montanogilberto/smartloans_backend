from fastapi import APIRouter
from modules.journalEntries import (
    journal_entries_sp, all_journal_entries_sp, one_journal_entry_sp,
    journal_entries_ledger_sp, journal_entries_trial_balance_sp,
)

router = APIRouter()


@router.post(
    "/journalEntries",
    summary="Journal Entries CRUD (Asientos Contables, partida doble)",
    description="""
action 1 — post (INSERT-only; the whole point of a ledger):
  { "journalEntries": [{ "action": 1, "companyId": int, "entryDate": "YYYY-MM-DD",
    "description": str, "referenceType"?: "income|expense|manual|adjustment|opening_balance",
    "referenceId"?: int, "createdByUserId"?: int,
    "lines": [{ "accountId": int, "debit": number, "credit": number, "lineDescription"?: str }, ...] }] }
  Rejected (RAISERROR + rollback) unless SUM(lines.debit) = SUM(lines.credit).
action 2 — void (the ONLY allowed update — entries are otherwise immutable once POSTED):
  { "journalEntries": [{ "action": 2, "entryId": int, "companyId": int, "status": "VOID" }] }
action 3 — always rejected. Corrections are a new reversing journalEntry.
""",
)
def journal_entries(json: dict):
    return journal_entries_sp(json)


@router.post(
    "/all_journalEntries",
    summary="Libro Diario — journal entry headers, filterable",
    description="""Body: { "journalEntries": [{ "companyId": int, "fromDate"?: "YYYY-MM-DD",
    "toDate"?: "YYYY-MM-DD", "referenceType"?: str, "status"?: "POSTED|VOID" }] }
Ordered by entryDate/entryNumber descending. No lines — use /journalEntries/one for the detail drill-down.""",
)
def all_journal_entries(json: dict):
    return all_journal_entries_sp(json)


@router.post(
    "/journalEntries/one",
    summary="Journal entry detail (header + Debe/Haber lines)",
    description="""Body: { "journalEntries": [{ "entryId": int }] }
The Movimiento -> Asiento drill-down target.""",
)
def one_journal_entry(json: dict):
    return one_journal_entry_sp(json)


@router.post(
    "/journalEntries/ledger",
    summary="Libro Mayor (read projection, not a stored table)",
    description="""Body: { "journalEntries": [{ "companyId": int, "fromDate"?: str, "toDate"?: str,
    "accountId"?: int }] }
Movements per account with a running balance (signed per the account's normalBalance).
The frontend groups the flat "movements" array by accountId.""",
)
def journal_entries_ledger(json: dict):
    return journal_entries_ledger_sp(json)


@router.post(
    "/journalEntries/trial-balance",
    summary="Balanza de Comprobación (read projection, not a stored table)",
    description="""Body: { "journalEntries": [{ "companyId": int, "toDate"?: str }] }
Returns { accounts: [...], totalDebit, totalCredit, balanced }. "balanced" should always
be true if every posted entry passed sp_journalEntries action=1's Debe=Haber check.""",
)
def journal_entries_trial_balance(json: dict):
    return journal_entries_trial_balance_sp(json)
