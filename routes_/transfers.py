from fastapi import APIRouter
from modules.transfers import (
    disburse_payment, payment_status, all_transfers_sp, one_transfer_sp,
)

router = APIRouter()


@router.post(
    "/payments/disburse",
    summary="SPEI dispersión (orchestrated, idempotent)",
    description="""
Ledger-first money out: replay check → default VERIFIED bank account of the
recipient → wallet debit (no overdraft) → transfer row → STP send (MOCK mode
until credentials exist) → settled+CEP, or automatic ledger REVERSAL on failure.

loan_disbursement (default) — lender wallet → borrower's bank:
  { "companyId": int, "lenderId": int, "borrowerId": int, "amountMXN": float,
    "loanId"?: int, "idempotencyKey": str }
lender_payout / refund — own wallet → own bank:
  { "companyId": int, "clientId": int, "amountMXN": float,
    "purpose": "lender_payout", "idempotencyKey": str }
""",
)
async def payments_disburse(json: dict):
    return await disburse_payment(json)


@router.post(
    "/payments/status",
    summary="Transfer status by id or idempotencyKey",
    description="""Body: { "companyId": int, "transferId"?: int, "idempotencyKey"?: str }""",
)
async def payments_status(json: dict):
    return await payment_status(json)


@router.post(
    "/all_transfers",
    summary="List transfers",
    description="""Body: { "transfers": [{ "companyId": int, "toClientId"?: int,
  "status"?: str, "purpose"?: str }] }""",
)
def all_transfers(json: dict):
    return all_transfers_sp(json)


@router.post(
    "/one_transfer",
    summary="One transfer",
    description="""Body: { "transfers": [{ "companyId": int, "transferId"?: int,
  "idempotencyKey"?: str }] }""",
)
def one_transfer(json: dict):
    return one_transfer_sp(json)
