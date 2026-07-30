from fastapi import APIRouter
from modules.bankAccounts import (
    link_bank_account, verify_bank_account, bank_accounts_sp, all_bank_accounts_sp,
)

router = APIRouter()


@router.post(
    "/bank-account/link",
    summary="Link a CLABE (starts micro-deposit verification)",
    description="""
Validates the 18-digit CLABE (check digit), resolves the bank from the ABM
prefix and creates the account in pending_verification with a 1–99 centavos
micro-deposit code. In MOCK mode (no STP credentials) the code is returned as
mockVerificationCents so the flow is testable.

Body: { "clientId": int, "companyId": int, "clabe": "18 digits", "holderName": str }
Returns: { bankAccountId, clabeLast4, bankName, status: "pending_verification", … }
""",
)
async def bank_account_link(json: dict):
    return await link_bank_account(json)


@router.post(
    "/bank-account/verify",
    summary="Verify a CLABE by micro-deposit amount",
    description="""
Body: { "clientId": int, "companyId": int, "bankAccountId": int, "amountCents": int }
On match: marks the account verified (first verified account becomes default).
Returns: { verified: true, … } | { verified: false, error }
""",
)
async def bank_account_verify(json: dict):
    return await verify_bank_account(json)


@router.post(
    "/bankAccounts",
    summary="Bank Accounts CRUD",
    description="""
action 1 — create (prefer /bank-account/link, which validates the CLABE):
  { "bankAccounts": [{ "action": 1, "companyId": int, "clientId": int,
    "clabe": str, "holderName": str, … }] }
action 2 — update (set default / rename / verify flags):
  { "bankAccounts": [{ "action": 2, "bankAccountId": int, "companyId": int, "isDefault": true }] }
action 3 — soft delete:
  { "bankAccounts": [{ "action": 3, "bankAccountId": int, "companyId": int }] }
""",
)
def bank_accounts(json: dict):
    return bank_accounts_sp(json)


@router.post(
    "/all_bankAccounts",
    summary="List a client's bank accounts (CLABE masked to last 4)",
    description="""Body: { "bankAccounts": [{ "companyId": int, "clientId"?: int }] }""",
)
def all_bank_accounts(json: dict):
    return all_bank_accounts_sp(json)
