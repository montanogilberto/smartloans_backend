from fastapi import APIRouter, BackgroundTasks, Depends, Header, HTTPException, Request
from modules.walletTopUps import confirm_transfer, credit_cash, credit_terminal, notify_top_up, reject_evidence
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


def _ticket(background_tasks: BackgroundTasks):
    """Sends the client's ticket after the response, so the cashier never waits on it."""
    return lambda data: background_tasks.add_task(notify_top_up, data)


@router.post("/transfer/confirm", summary="Staff confirms a transfer top-up", dependencies=[Depends(_require_company_staff)])
def confirm(request: Request, json: dict, background_tasks: BackgroundTasks):
    return confirm_transfer(_acting_user(request, json), notify=_ticket(background_tasks))


@router.post("/cash", summary="Staff records a cash top-up", dependencies=[Depends(_require_company_staff)])
def cash(request: Request, json: dict, background_tasks: BackgroundTasks):
    return credit_cash(_acting_user(request, json), notify=_ticket(background_tasks))


@router.post("/terminal", summary="Staff records a top-up charged on the terminal",
             dependencies=[Depends(_require_company_staff)])
def terminal(request: Request, json: dict, background_tasks: BackgroundTasks):
    return credit_terminal(_acting_user(request, json), notify=_ticket(background_tasks))


@router.post("/transfer/reject", summary="Staff rejects a comprobante", dependencies=[Depends(_require_company_staff)])
def reject(request: Request, json: dict):
    return reject_evidence(_acting_user(request, json))
