from fastapi import APIRouter, Depends, Header, HTTPException, Request
from modules.walletTopUps import confirm_transfer, reject_evidence
from security.session_tokens import _as_int, _bearer, decode
from security.worker_key import require_worker_key

router = APIRouter(prefix="/walletTopUps", tags=["Wallet top-ups"])

_STAFF_ROLES = {"admin", "manager", "employee"}


async def _require_company_staff(request: Request, x_worker_key: str | None = Header(default=None)) -> None:
    """Credits money, so a client session can never reach it: staff of that company
    only. The company comes from the signed token, checked against the body."""
    token = _bearer(request)
    if not token:
        require_worker_key(x_worker_key)
        return
    claims = decode(token, "access")
    if claims is None:
        raise HTTPException(status_code=401, detail="Session expired")
    body = await request.json()
    allowed = {_as_int(c.get("companyId")) for c in claims.get("companies") or []
               if str(c.get("role") or "").strip().lower() in _STAFF_ROLES}
    if _as_int(body.get("companyId")) not in allowed - {0}:
        raise HTTPException(status_code=403, detail="Forbidden")


def _acting_user(request: Request, json: dict) -> dict:
    claims = decode(_bearer(request), "access")
    return {**json, "userId": int(claims["sub"])} if claims else json


@router.post("/transfer/confirm", summary="Staff confirms a transfer top-up", dependencies=[Depends(_require_company_staff)])
def confirm(request: Request, json: dict):
    return confirm_transfer(_acting_user(request, json))


@router.post("/transfer/reject", summary="Staff rejects a comprobante", dependencies=[Depends(_require_company_staff)])
def reject(request: Request, json: dict):
    return reject_evidence(_acting_user(request, json))
