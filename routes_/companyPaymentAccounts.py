from fastapi import APIRouter, Depends, HTTPException, Request
from modules.companyPaymentAccounts import active_accounts, add_transfer_account
from modules.stripe_payments import company_onboarding_link, confirm_company_account, list_company_accounts
from security.session_tokens import _bearer, decode, require_company_admin_on_write

router = APIRouter(prefix="/companyPaymentAccounts", tags=["Company payment accounts"])

# Decides where customers' money lands: every route but /active needs an admin
# session of that company, or the worker key.
async def _reject_read_shaped_body(request: Request) -> None:
    """The shared guard leaves rows with no action open as reads. Nothing here is
    an open read, so a body shaped like one must not get past it."""
    try:
        body = await request.json()
    except Exception:
        body = None
    rows = body.get("companyPaymentAccounts") if isinstance(body, dict) else None
    if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict) \
            or rows[0].get("action") in (None, 0, "0"):
        raise HTTPException(status_code=403, detail="Forbidden")


_admin = [Depends(_reject_read_shaped_body), Depends(require_company_admin_on_write("companyPaymentAccounts"))]


def _session_user(request: Request, body: dict, field: str) -> dict:
    """The acting admin comes from the signed session, never from the body."""
    claims = decode(_bearer(request), "access")
    if claims:
        body["companyPaymentAccounts"][0][field] = int(claims["sub"])
    return body


@router.post("/active", summary="Whether card top-ups are available")
def active(json: dict):
    return active_accounts(json)


@router.post("/list", summary="Company accounts (admin)", dependencies=_admin)
async def list_all(json: dict):
    return await list_company_accounts(json)


@router.post("/confirm", summary="Second admin activates an account", dependencies=_admin)
async def confirm(request: Request, json: dict):
    return await confirm_company_account(_session_user(request, json, "verifiedByUserId"))


@router.post("/transfer-account", summary="Register the company's CLABE (pending)", dependencies=_admin)
def transfer_account(request: Request, json: dict):
    return add_transfer_account(_session_user(request, json, "createdByUserId"))


@router.post("/stripe/onboarding-link", summary="Connect the company's Stripe account", dependencies=_admin)
async def onboarding_link(request: Request, json: dict):
    return await company_onboarding_link(_session_user(request, json, "createdByUserId"))
