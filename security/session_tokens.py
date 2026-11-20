"""Signed session tokens (HS256, SESSION_JWT_SECRET).

Three kinds, told apart by the `typ` claim so one can never stand in for another:
  access   ~30 min, sent as Authorization: Bearer on every call
  refresh  30 days, only accepted by POST /auth/refresh
  set_pin  10 min, proves an SMS code was verified, only accepted by /set_client_password

Without a usable secret nothing is issued and every token is rejected.
"""
import logging
import os
import time
from typing import Any, Iterable, Optional

import jwt
from fastapi import Header, HTTPException, Request

from security.worker_key import require_worker_key

logger = logging.getLogger("session_tokens")

ACCESS_SECONDS = 30 * 60
REFRESH_SECONDS = 30 * 24 * 3600
SET_PIN_SECONDS = 10 * 60

_ALGORITHM = "HS256"
_ISSUER = "smartloans"
_MIN_SECRET_LENGTH = 32


def _secret() -> str:
    value = os.getenv("SESSION_JWT_SECRET", "")
    return value if len(value) >= _MIN_SECRET_LENGTH else ""


def _encode(claims: dict, token_type: str, seconds: int) -> Optional[str]:
    secret = _secret()
    if not secret:
        logger.warning("[session_tokens] SESSION_JWT_SECRET is missing or too short: no token issued")
        return None
    now = int(time.time())
    return jwt.encode({**claims, "typ": token_type, "iss": _ISSUER, "iat": now, "exp": now + seconds},
                      secret, algorithm=_ALGORITHM)


def _as_int(value: object) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def resolve_push_user_ids(*args: Any, **kwargs: Any) -> list[int]:
    """Normalize candidate user IDs into a deduplicated list of positive ints.

    Replace or extend this implementation once you confirm the exact payload or
    database lookup expected by `modules/loanPayments.py`.
    """
    candidates: list[Any] = []

    for key in ("user_ids", "userIds", "recipient_ids", "recipientIds", "user_id", "userId"):
        if key in kwargs and kwargs[key] is not None:
            candidates.append(kwargs[key])

    for arg in args:
        if arg is not None:
            candidates.append(arg)

    resolved: list[int] = []
    seen: set[int] = set()

    def _collect(item: Any) -> None:
        if item is None:
            return
        if isinstance(item, dict):
            for field in ("userId", "user_id", "id", "targetUserId", "target_user_id"):
                if field in item:
                    _collect(item[field])
            for list_field in ("userIds", "user_ids", "recipientIds", "recipient_ids"):
                if list_field in item:
                    _collect(item[list_field])
            return
        if isinstance(item, (list, tuple, set)) or (isinstance(item, Iterable) and not isinstance(item, (str, bytes))):
            for sub in item:
                _collect(sub)
            return
        uid = _as_int(item)
        if uid > 0 and uid not in seen:
            seen.add(uid)
            resolved.append(uid)

    for entry in candidates:
        _collect(entry)

    return resolved


def issue_session(user_id: object, company_id: object = 0, client_id: object = 0, role: object = "") -> Optional[dict]:
    """{ accessToken, refreshToken, expiresIn } or None when tokens can't be issued."""
    claims = {
        "sub": str(user_id),
        "clientId": _as_int(client_id),
        "companies": [{"companyId": _as_int(company_id), "role": str(role or "")}],
    }
    access = _encode(claims, "access", ACCESS_SECONDS)
    refresh = _encode(claims, "refresh", REFRESH_SECONDS)
    if not access or not refresh:
        return None
    return {"accessToken": access, "refreshToken": refresh, "expiresIn": ACCESS_SECONDS}


def reissue_session(refresh_claims: dict) -> Optional[dict]:
    company = (refresh_claims.get("companies") or [{}])[0]
    return issue_session(refresh_claims.get("sub"), company.get("companyId"),
                         refresh_claims.get("clientId"), company.get("role"))


def issue_set_pin_token(user_id: object) -> Optional[str]:
    return _encode({"sub": str(user_id)}, "set_pin", SET_PIN_SECONDS)


def decode(token: object, token_type: str) -> Optional[dict]:
    """The claims of a valid, unexpired token of this kind, else None."""
    secret = _secret()
    if not secret or not token or not isinstance(token, str):
        return None
    try:
        claims = jwt.decode(token, secret, algorithms=[_ALGORITHM], issuer=_ISSUER,
                            options={"require": ["exp", "iat", "iss", "sub"]})
    except jwt.InvalidTokenError:
        return None
    return claims if claims.get("typ") == token_type else None


def set_pin_token_required() -> bool:
    return os.getenv("AUTH_REQUIRE_PIN_TOKEN", "").strip().lower() in ("1", "true")


def _bearer(request: Request) -> str:
    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    return token.strip() if scheme.lower() == "bearer" else ""


async def require_session_or_worker_key(request: Request, x_worker_key: str | None = Header(default=None)) -> None:
    """A session may only act for its own userId. The worker key stays accepted
    for app versions released before session tokens."""
    token = _bearer(request)
    if not token:
        require_worker_key(x_worker_key)
        return
    claims = decode(token, "access")
    if claims is None:
        # 401, not 403: it is what makes the app refresh its token and retry.
        raise HTTPException(status_code=401, detail="Session expired")
    try:
        body = await request.json()
    except Exception:
        body = None
    if not isinstance(body, dict) or str(body.get("userId")) != claims["sub"]:
        raise HTTPException(status_code=403, detail="Forbidden")


_COMPANY_ADMIN_ROLES = {"admin", "manager"}  # same roles as the POS "Agente WhatsApp" screens


def require_company_admin_on_write(key: str):
    """Guards a catalog endpoint whose body is {key: [{action, companyId, ...}]}.
    Reads stay open: the agent and the kiosk call them. A write needs the worker
    key, or a session of an admin/manager of that row's company. This data reaches
    customers (the CLABE to pay to, for one), so the company comes from the signed
    token, never from the X-Company-Id header."""
    async def guard(request: Request, x_worker_key: str | None = Header(default=None)) -> None:
        try:
            body = await request.json()
        except Exception:
            body = None
        rows = body.get(key) if isinstance(body, dict) else None
        rows = rows if isinstance(rows, list) and rows and all(isinstance(r, dict) for r in rows) else None
        if rows and all(r.get("action") in (None, 0, "0") for r in rows):
            return
        token = _bearer(request)
        if not token:
            require_worker_key(x_worker_key)
            return
        claims = decode(token, "access")
        if claims is None:
            raise HTTPException(status_code=401, detail="Session expired")
        allowed = {_as_int(c.get("companyId")) for c in claims.get("companies") or []
                   if str(c.get("role") or "").strip().lower() in _COMPANY_ADMIN_ROLES}
        allowed.discard(0)
        if not rows or any(_as_int(r.get("companyId")) not in allowed for r in rows):
            raise HTTPException(status_code=403, detail="Forbidden")
    return guard


_COMPANY_STAFF_ROLES = {"admin", "manager", "employee", "business"}  # POS staff (rolePermissions.ts STAFF_ROLES minus viewer)


def require_company_staff_session(key: str, roles: set[str] | None = None):
    """Guards an endpoint that acts on a customer for a company (a phone call):
    body {key: [{companyId, userId, ...}]}. Needs the worker key, or an access
    token of a staff member of that company whose userId is the token's. The
    company comes from the signed token, never from X-Company-Id. roles narrows
    which company roles count (default: all POS staff roles)."""
    staff_roles = _COMPANY_STAFF_ROLES if roles is None else {r.strip().lower() for r in roles}

    async def guard(request: Request, x_worker_key: str | None = Header(default=None)) -> None:
        token = _bearer(request)
        if not token:
            require_worker_key(x_worker_key)
            return
        claims = decode(token, "access")
        if claims is None:
            raise HTTPException(status_code=401, detail="Session expired")
        try:
            body = await request.json()
        except Exception:
            body = None
        rows = body.get(key) if isinstance(body, dict) else None
        row = rows[0] if isinstance(rows, list) and len(rows) == 1 and isinstance(rows[0], dict) else None
        allowed = {_as_int(c.get("companyId")) for c in claims.get("companies") or []
                   if str(c.get("role") or "").strip().lower() in staff_roles}
        allowed.discard(0)
        if (row is None or str(row.get("userId")) != claims["sub"]
                or _as_int(row.get("companyId")) not in allowed):
            raise HTTPException(status_code=403, detail="Forbidden")
    return guard


# RFC-011 P1.1 — walletTransactions is the saldo the machines (and, later, the
# register) spend, so a forged credit is free merchandise.
_LEDGER_READ_ROLES = {"admin", "manager", "employee", "business", "viewer"}
_LEDGER_WRITE_ROLES = {"admin", "manager"}
# What a client may write on their OWN ledger: the lender's capital history,
# which sp_walletTransactions keeps out of the spendable balance.
_LEDGER_SELF_WRITE_TYPES = {"CAPITAL_DECLARED", "CAPITAL_UNDECLARED"}
# The lender screen's "simulated SPEI deposit" test tool: never in production.
_LEDGER_SELF_WRITE_TYPES_DEV = {"DEPOSIT"}


def _ledger_row_allowed(row: dict, claims: dict, write: bool, is_prod: bool) -> bool:
    company_id = _as_int(row.get("companyId"))
    if not company_id:
        return False
    roles = {str(c.get("role") or "").strip().lower() for c in claims.get("companies") or []
             if _as_int(c.get("companyId")) == company_id}
    if not roles:
        return False  # the company comes from the signed token, never from the body
    if roles & (_LEDGER_WRITE_ROLES if write else _LEDGER_READ_ROLES):
        return True
    own_client = _as_int(claims.get("clientId"))
    if not own_client or _as_int(row.get("clientId")) != own_client:
        return False
    if not write:
        return True
    entry_type = str(row.get("entryType") or "").strip().upper()
    return entry_type in _LEDGER_SELF_WRITE_TYPES or (not is_prod and entry_type in _LEDGER_SELF_WRITE_TYPES_DEV)


def require_wallet_ledger_access(write: bool):
    """Guards POST /walletTransactions (write) and /all_walletTransactions (read):
    body {"walletTransactions": [{companyId, clientId, ...}]}. Worker key (the
    agents service), or a session that is staff of that company (writes: admin/
    manager), or the client's own ledger (writes: only the types above)."""
    async def guard(request: Request, x_worker_key: str | None = Header(default=None)) -> None:
        token = _bearer(request)
        if not token:
            require_worker_key(x_worker_key)
            return
        claims = decode(token, "access")
        if claims is None:
            raise HTTPException(status_code=401, detail="Session expired")
        try:
            body = await request.json()
        except Exception:
            body = None
        rows = body.get("walletTransactions") if isinstance(body, dict) else None
        if not isinstance(rows, list) or not rows or not all(isinstance(r, dict) for r in rows):
            raise HTTPException(status_code=403, detail="Forbidden")
        from app_env import IS_PROD
        if not all(_ledger_row_allowed(r, claims, write, IS_PROD) for r in rows):
            logger.warning("[session_tokens] walletTransactions %s refused for user %s",
                           "write" if write else "read", claims.get("sub"))
            raise HTTPException(status_code=403, detail="Forbidden")
    return guard


# Platform-wide catalogs (dbo.agents): one list for every company, owned by
# SmartLoans. Only an admin of the SmartLoans company may change them.
PLATFORM_COMPANY_ID = 1008


def _staff_companies(claims: dict, roles: set[str]) -> set[int]:
    ids = {_as_int(c.get("companyId")) for c in claims.get("companies") or []
           if str(c.get("role") or "").strip().lower() in roles}
    ids.discard(0)
    return ids


def is_platform_admin(claims: dict | None) -> bool:
    return bool(claims) and PLATFORM_COMPANY_ID in _staff_companies(claims, {"admin"})


async def require_platform_admin_session(request: Request) -> dict:
    """Writes to a platform catalog: an access token of an admin of SmartLoans
    (companyId 1008). No worker key: the agents service only reads."""
    claims = decode(_bearer(request), "access")
    if claims is None:
        raise HTTPException(status_code=401, detail="Session expired")
    if not is_platform_admin(claims):
        raise HTTPException(status_code=403, detail="Forbidden")
    return claims


async def require_staff_session_or_worker_key(request: Request, x_worker_key: str | None = Header(default=None)) -> None:
    """Reads of a platform catalog: any POS staff session, or the worker key."""
    token = _bearer(request)
    if not token:
        require_worker_key(x_worker_key)
        return
    claims = decode(token, "access")
    if claims is None:
        raise HTTPException(status_code=401, detail="Session expired")
    if not _staff_companies(claims, _COMPANY_STAFF_ROLES):
        raise HTTPException(status_code=403, detail="Forbidden")


def require_company_rows_or_platform_admin(key: str, roles: set[str], allow_worker_key: bool):
    """Per-company settings over a platform catalog (dbo.agentCompanySettings):
    body {key: [{companyId, ...}]}. Every row's companyId must be a company the
    signed token holds with one of `roles`, or the token is a SmartLoans admin
    (who may act for any company). The company comes from the token, never from
    X-Company-Id. allow_worker_key: the agents service may call without a token.
    Returns the token claims (None for the worker key) so the route can stamp
    updatedByUserId from `sub`."""
    wanted = {r.strip().lower() for r in roles}

    async def guard(request: Request, x_worker_key: str | None = Header(default=None)) -> dict | None:
        token = _bearer(request)
        if not token:
            if not allow_worker_key:
                raise HTTPException(status_code=401, detail="Session required")
            require_worker_key(x_worker_key)
            return None
        claims = decode(token, "access")
        if claims is None:
            raise HTTPException(status_code=401, detail="Session expired")
        try:
            body = await request.json()
        except Exception:
            body = None
        rows = body.get(key) if isinstance(body, dict) else None
        if not isinstance(rows, list) or not rows or not all(isinstance(r, dict) for r in rows):
            raise HTTPException(status_code=403, detail="Forbidden")
        if is_platform_admin(claims):
            return claims
        allowed = _staff_companies(claims, wanted)
        if any(_as_int(r.get("companyId")) not in allowed for r in rows):
            raise HTTPException(status_code=403, detail="Forbidden")
        return claims
    return guard


def require_client_rows_access(key: str, client_may_access: bool):
    """Personal data of one client (dbo.addresses): body {key: [{companyId,
    clientId, ...}]}, exactly one row. Needs the worker key, or an access token
    that is staff of that row's company (or a SmartLoans admin), or — when
    client_may_access — the client themself (token clientId == row clientId, in
    a company the token holds). The ids come from the signed token, never from
    the X-* observability headers."""
    async def guard(request: Request, x_worker_key: str | None = Header(default=None)) -> None:
        token = _bearer(request)
        if not token:
            require_worker_key(x_worker_key)
            return
        claims = decode(token, "access")
        if claims is None:
            raise HTTPException(status_code=401, detail="Session expired")
        try:
            body = await request.json()
        except Exception:
            body = None
        rows = body.get(key) if isinstance(body, dict) else None
        row = rows[0] if isinstance(rows, list) and len(rows) == 1 and isinstance(rows[0], dict) else None
        if row is None:
            raise HTTPException(status_code=403, detail="Forbidden")
        company_id = _as_int(row.get("companyId"))
        if is_platform_admin(claims) or (company_id and company_id in _staff_companies(claims, _COMPANY_STAFF_ROLES)):
            return
        own_companies = {_as_int(c.get("companyId")) for c in claims.get("companies") or []}
        if (client_may_access and company_id and company_id in own_companies
                and _as_int(claims.get("clientId")) and _as_int(claims.get("clientId")) == _as_int(row.get("clientId"))):
            return
        raise HTTPException(status_code=403, detail="Forbidden")
    return guard