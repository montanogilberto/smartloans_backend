"""Lender platform fee routes — RFC-016 fase 3b. See modules/platformFees.py.

Deliberately NOT exposed: any route that writes sp_platformFees directly (create,
status, mark paid). Fees are created and charged by the backend when the loan
contract is generated, and only the signature-verified /stripe/webhook marks them
PAID or REFUNDED — a client-facing write route would let anyone unlock funding.
"""
from fastapi import APIRouter, Depends, HTTPException, Request

from modules import platformFees as fees
from security.session_tokens import _bearer, decode, require_company_staff_session

router = APIRouter(tags=["Platform Fees"])


async def _session_client_id(request: Request) -> int:
    """The clientId of the signed-in app user (access token). Lender routes act
    only on that client's own fees — never on a clientId sent in the body."""
    claims = decode(_bearer(request), "access")
    if claims is None:
        raise HTTPException(status_code=401, detail="Session expired")
    client_id = int(claims.get("clientId") or 0)
    if not client_id:
        raise HTTPException(status_code=403, detail="Forbidden")
    return client_id


@router.post("/platformFees/card/setup-intent", summary="SetupIntent for the lender's fee card")
async def fee_card_setup_intent(json: dict, client_id: int = Depends(_session_client_id)):
    return await fees.create_fee_card_setup_intent(json, client_id)


@router.post("/platformFees/by-loan", summary="The signed-in lender's fee for a loan")
async def fee_by_loan(json: dict, client_id: int = Depends(_session_client_id)):
    return await fees.get_fee(json, client_id)


@router.post("/platformFees/retry", summary="Charge the lender's saved card again (after adding a card)")
async def fee_retry(json: dict, client_id: int = Depends(_session_client_id)):
    return await fees.retry_fee(json, client_id)


@router.post("/platformFees/client-secret", summary="client_secret to confirm a pending fee on-session (3-D Secure)")
async def fee_client_secret(json: dict, client_id: int = Depends(_session_client_id)):
    return await fees.fee_client_secret(json, client_id)


# Admin reads (Admin/Manager staff of the company, or the worker key).
@router.post("/all_platformFees", summary="All platform fees of a company",
             dependencies=[Depends(require_company_staff_session("platformFees", {"admin", "manager"}))])
def all_platform_fees(json: dict):
    return fees.all_fees(json)


@router.post("/one_platformFees", summary="One platform fee",
             dependencies=[Depends(require_company_staff_session("platformFees", {"admin", "manager"}))])
def one_platform_fee(json: dict):
    return fees.one_fee(json)
