from fastapi import APIRouter
from modules.walletBalance import get_wallet, credit_wallet, debit_wallet, reserve_wallet, release_wallet, get_all_wallets

router = APIRouter(prefix="/wallet", tags=["Wallet Balance"])


@router.post(
    "",
    summary="Get wallet balance for a client",
    description="""
Returns the platform wallet balance for a lender or borrower.

Body: { "clientId": int, "companyId": int }
Returns: { "wallet": { availableBalance, reservedBalance, totalTopUps, totalDisbursed, totalRepaid } }
""",
)
async def wallet(json: dict):
    return await get_wallet(json)


@router.post(
    "/all",
    summary="List all wallet balances for a company (admin)",
    description="Body: { \"companyId\": int }",
)
async def all_wallets(json: dict):
    return await get_all_wallets(json)


@router.post(
    "/credit",
    summary="Credit wallet after top-up or repayment received",
    description="""
Called internally after Stripe webhook confirms payment_intent.succeeded.
type: 'top_up' | 'repayment_received'

Body: { "clientId": int, "companyId": int, "amountMXN": float, "type": str }
""",
)
async def credit(json: dict):
    return await credit_wallet(json)


@router.post(
    "/debit",
    summary="Debit wallet after loan disbursement or withdrawal",
    description="""
Called internally after stripe/disburse succeeds.
type: 'disbursement' | 'withdrawal'

Body: { "clientId": int, "companyId": int, "amountMXN": float, "type": str }
""",
)
async def debit(json: dict):
    return await debit_wallet(json)


@router.post(
    "/reserve",
    summary="Reserve funds when a proposal is accepted",
    description="""
Moves amountMXN from availableBalance to reservedBalance.
Called when lender accepts a borrower's proposal (before disbursement).

Body: { "clientId": int, "companyId": int, "amountMXN": float }
""",
)
async def reserve(json: dict):
    return await reserve_wallet(json)


@router.post(
    "/release",
    summary="Release a reservation when disbursement fails",
    description="""
Moves amountMXN from reservedBalance back to availableBalance without
touching totalDisbursed. Called when a /stripe/disburse call fails after
funds were already reserved for it.

Body: { "clientId": int, "companyId": int, "amountMXN": float }
""",
)
async def release(json: dict):
    return await release_wallet(json)
