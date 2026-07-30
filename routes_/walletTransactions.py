from fastapi import APIRouter
from modules.walletTransactions import (
    wallet_transactions_sp, all_wallet_transactions_sp, ledger_balance,
)

router = APIRouter()


@router.post(
    "/walletTransactions",
    summary="Ledger entry (INSERT-only)",
    description="""
Immutable money ledger — action 1 (insert) is the ONLY mutation; the SP rejects
update/delete. Corrections are new REVERSAL entries. Replaying the same
idempotencyKey returns the original entry (replayed: true), never a double post.
Debits that would overdraw return { error: "Saldo insuficiente" }.

Body: { "walletTransactions": [{ "action": 1, "companyId": int, "clientId": int|null,
  "entryType": "DEPOSIT|RESERVE|RELEASE|LOAN_FUNDING|DISBURSEMENT_RECEIVED|
                REPAYMENT_PRINCIPAL|REPAYMENT_INTEREST|PLATFORM_FEE|WITHDRAWAL|
                REFUND|REVERSAL|ADJUSTMENT",
  "direction": "D|C", "amountMXN": float, "idempotencyKey": str,
  "referenceType"?: str, "referenceId"?: int, "note"?: str }] }
""",
)
def wallet_transactions(json: dict):
    return wallet_transactions_sp(json)


@router.post(
    "/all_walletTransactions",
    summary="Movement statement (newest first, top 200)",
    description="""Body: { "walletTransactions": [{ "companyId": int, "clientId"?: int,
  "entryType"?: str }] }  — clientId omitted/null = platform ledger.""",
)
def all_wallet_transactions(json: dict):
    return all_wallet_transactions_sp(json)


@router.post(
    "/ledger/balance",
    summary="Balance projection over the ledger",
    description="""Body: { "companyId": int, "clientId"?: int }
Returns: { availableBalance, reservedBalance }""",
)
async def balance(json: dict):
    return await ledger_balance(json)
