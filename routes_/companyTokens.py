from fastapi import APIRouter, Depends

from modules.companyTokens import (
    company_tokens_balance_sp, company_tokens_record_sp, company_tokens_topup_sp,
)
from security.worker_key import require_worker_key

router = APIRouter()


@router.post(
    "/company_tokens/balance",
    summary="AI-token balance for a company",
    description="""
Body: { "tokens": [{ "companyId": int }] }
Returns: { ok, companyId, balance, usedToday, usedThisMonth, callsThisMonth,
           lastTopupTokens?, lastTopupAt? }

balance is the sum of the company's append-only token ledger (top-ups minus
agent usage). Today / this month are Hermosillo calendar periods. A company
with no ledger rows reports balance 0. Read-only.
""",
)
def company_tokens_balance(json: dict):
    return company_tokens_balance_sp(json)


@router.post(
    "/company_tokens/record",
    summary="Record one agent call's token usage (server-to-server)",
    description="""
Body: { "tokens": [{ "companyId": int, "agentName"?: str, "endpointName"?: str,
        "model"?: str, "inputTokens": int, "outputTokens": int,
        "thoughtsTokens"?: int, "reference"?: str }] }
Returns: { recorded, tokens, balance } or { recorded: false, error }

Called by the LoanAgents SmartLoans service after each agent run. Requires the
X-Worker-Key header (same shared secret the workers use): a client must never
be able to fabricate usage.
""",
)
def company_tokens_record(json: dict, worker_ok=Depends(require_worker_key)):
    return company_tokens_record_sp(json)


@router.post(
    "/company_tokens/topup",
    summary="Add tokens to a company's balance (server-side only)",
    description="""
Body: { "tokens": [{ "companyId": int, "tokens": int > 0, "notes"?: str,
        "userId"?: int, "entryType"?: "topup" | "adjustment" }] }
Returns: { ok, balance } or { ok: false, error }

Requires X-Worker-Key. Only entryType='adjustment' may be negative (a
correction); every change is a new ledger row, never an edit.
""",
)
def company_tokens_topup(json: dict, worker_ok=Depends(require_worker_key)):
    return company_tokens_topup_sp(json)
