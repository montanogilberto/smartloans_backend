# security/session_tokens.py
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
from typing import Optional

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
