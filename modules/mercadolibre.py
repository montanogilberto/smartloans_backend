"""
modules/mercadolibre.py

Dynamic PKCE OAuth for Mercado Libre:
- Generate authorize URL with PKCE + state
- Persist state -> code_verifier
- Callback exchanges code -> tokens
- Store tokens and auto-refresh
"""

import os
import json
import logging
import base64
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional, Tuple

import requests
from databases import connection

logger = logging.getLogger(__name__)

# ---------------------------------------------------------
# ENV
# ---------------------------------------------------------
ML_CLIENT_ID = os.getenv("ML_CLIENT_ID", "").strip()
ML_CLIENT_SECRET = os.getenv("ML_CLIENT_SECRET", "").strip()
ML_REDIRECT_URI = os.getenv("ML_REDIRECT_URI", "").strip()

AUTH_URL = "https://auth.mercadolibre.com.mx/authorization"
TOKEN_URL = "https://api.mercadolibre.com/oauth/token"

logger.info("ML_CLIENT_ID loaded? %s", bool(ML_CLIENT_ID))
logger.info("ML_REDIRECT_URI loaded? %s", bool(ML_REDIRECT_URI))
logger.info("ML_CLIENT_SECRET loaded? %s", bool(ML_CLIENT_SECRET))


# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
def _get_conn():
    """
    Always returns a fresh DB connection.
    Avoids stale connections in Azure / FastAPI.
    """
    conn = connection()
    # DEBUGGING: Log connection details (without sensitive info)
    logger.info("[DB] Connection created - server: %s, database: %s",
               conn.server, conn.database)
    return conn


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")


# ---------------------------------------------------------
# PKCE
# ---------------------------------------------------------
def generate_pkce_pair() -> Tuple[str, str]:
    """
    Returns (code_verifier, code_challenge)
    """
    verifier = _b64url(secrets.token_bytes(32))
    challenge = _b64url(hashlib.sha256(verifier.encode("utf-8")).digest())
    return verifier, challenge


# ---------------------------------------------------------
# DB: OAuth state
# ---------------------------------------------------------
def _oauth_states_sp(payload: Dict[str, Any]) -> Dict[str, Any]:
    """EXEC sp_mlOAuthStates -> parsed jsonResult. Raises on SP error so
    callers keep the old raw-SQL behavior (DB failures propagate)."""
    with _get_conn() as conn:
        cur = conn.cursor()
        cur.execute("EXEC sp_mlOAuthStates @pjsonfile = %s",
                    (json.dumps({"mlOAuthStates": [payload]}),))
        row = cur.fetchone()
        result = json.loads(row[0]) if row and row[0] else {}
        if "error" in result:
            raise RuntimeError(f"sp_mlOAuthStates {payload.get('action')}: {result['error']}")
        return result


def save_oauth_state(state: str, code_verifier: str) -> None:
    _oauth_states_sp({"action": "save", "state": state, "code_verifier": code_verifier})
    logger.info("[DB] OAuth state saved - state: %s...", state[:8])


def pop_code_verifier(state: str) -> Optional[str]:
    # Atomic in the SP: marks used_at and returns the verifier in one
    # statement, so a replayed callback for the same state gets nothing.
    verifier = _oauth_states_sp({"action": "pop", "state": state}).get("code_verifier")

    if not verifier:
        logger.warning("[DB] No code_verifier found for state: %s", state[:8])
        return None

    logger.info("[DB] Code verifier retrieved and marked used - state: %s...", state[:8])
    return verifier


# ---------------------------------------------------------
# DB: Tokens
# ---------------------------------------------------------
def _tokens_sp(payload: Dict[str, Any]) -> Dict[str, Any]:
    """EXEC sp_mlTokens -> parsed jsonResult. Raises on SP error."""
    with _get_conn() as conn:
        cur = conn.cursor()
        cur.execute("EXEC sp_mlTokens @pjsonfile = %s",
                    (json.dumps({"mlTokens": [payload]}),))
        row = cur.fetchone()
        result = json.loads(row[0]) if row and row[0] else {}
        if "error" in result:
            raise RuntimeError(f"sp_mlTokens {payload.get('action')}: {result['error']}")
        return result


def upsert_tokens(token_json: Dict[str, Any]) -> None:
    access_token = token_json["access_token"]
    refresh_token = token_json["refresh_token"]
    expires_in = int(token_json.get("expires_in", 21600))
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=expires_in - 60)

    # Atomic in the SP (UPDLOCK probe + update-or-insert in one transaction).
    result = _tokens_sp({
        "action": "upsert",
        "access_token": access_token,
        "refresh_token": refresh_token,
        # naive UTC ISO-8601, same wall-clock value the old raw SQL stored
        "expires_at": expires_at.replace(tzinfo=None).isoformat(timespec="seconds"),
    })
    logger.info("[DB] Tokens %s - token_id: %s", result.get("op"), result.get("id"))


def get_latest_tokens() -> Optional[Dict[str, Any]]:
    tokens = _tokens_sp({"action": "latest"})

    if not tokens:
        logger.warning("[DB] No tokens found in database")
        return None

    # DEBUGGING: Log token retrieval (masked)
    token_len = len(tokens["access_token"]) if tokens.get("access_token") else 0
    logger.info("[DB] Tokens retrieved - has_access: %s, access_len: %s",
               bool(tokens.get("access_token")), token_len)

    return {
        "access_token": tokens.get("access_token"),
        "refresh_token": tokens.get("refresh_token"),
        # naive UTC; get_valid_access_token() attaches tzinfo
        "expires_at": datetime.fromisoformat(tokens["expires_at"]),
    }


# ---------------------------------------------------------
# OAuth
# ---------------------------------------------------------
def build_authorize_url() -> Dict[str, Any]:
    if not ML_CLIENT_ID or not ML_REDIRECT_URI:
        raise ValueError("Missing ML_CLIENT_ID or ML_REDIRECT_URI")

    state = _b64url(secrets.token_bytes(16))
    verifier, challenge = generate_pkce_pair()

    save_oauth_state(state, verifier)

    authorize_url = (
        f"{AUTH_URL}"
        f"?response_type=code"
        f"&client_id={ML_CLIENT_ID}"
        f"&redirect_uri={ML_REDIRECT_URI}"
        f"&code_challenge={challenge}"
        f"&code_challenge_method=S256"
        f"&state={state}"
    )

    return {
        "authorize_url": authorize_url,
        "state": state,
    }


def exchange_code_for_token(code: str, code_verifier: str) -> Dict[str, Any]:
    if not ML_CLIENT_ID or not ML_CLIENT_SECRET or not ML_REDIRECT_URI:
        raise ValueError("Missing ML_CLIENT_ID / ML_CLIENT_SECRET / ML_REDIRECT_URI")

    payload = {
        "grant_type": "authorization_code",
        "client_id": ML_CLIENT_ID,
        "client_secret": ML_CLIENT_SECRET,
        "code": code,
        "redirect_uri": ML_REDIRECT_URI,
        "code_verifier": code_verifier,
    }

    logger.info("[OAuth] Exchanging code for token - code_len: %s", len(code))

    r = requests.post(TOKEN_URL, data=payload, timeout=30)

    if r.status_code >= 400:
        raise RuntimeError(
            f"Token exchange failed ({r.status_code}): {r.text}"
        )

    logger.info("[OAuth] Token exchange successful")
    return r.json()


def refresh_access_token(refresh_token: str) -> Dict[str, Any]:
    payload = {
        "grant_type": "refresh_token",
        "client_id": ML_CLIENT_ID,
        "client_secret": ML_CLIENT_SECRET,
        "refresh_token": refresh_token,
    }

    logger.info("[OAuth] Refreshing token - refresh_len: %s", len(refresh_token))

    r = requests.post(TOKEN_URL, data=payload, timeout=30)

    if r.status_code >= 400:
        raise RuntimeError(
            f"Token refresh failed ({r.status_code}): {r.text}"
        )

    logger.info("[OAuth] Token refresh successful")
    return r.json()


def get_valid_access_token() -> str:
    """
    This is the method your workers should call.
    Always returns a valid access_token.
    """
    tokens = get_latest_tokens()

    if not tokens:
        raise RuntimeError("No Mercado Libre tokens found. Run OAuth flow first.")

    expires_at = tokens["expires_at"]
    now = datetime.now(timezone.utc)

    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)

    # DEBUGGING: Log token status
    token_len = len(tokens["access_token"]) if tokens["access_token"] else 0
    logger.info("[Token] Current token status - has_token: %s, token_len: %s, expires_at: %s, now: %s",
               bool(tokens["access_token"]), token_len, expires_at, now)

    if now < expires_at:
        logger.info("[Token] Using cached token - still valid")
        return tokens["access_token"]

    # refresh expired token
    logger.info("[Token] Token expired, refreshing...")
    new_tokens = refresh_access_token(tokens["refresh_token"])
    upsert_tokens(new_tokens)

    new_token_len = len(new_tokens["access_token"]) if new_tokens["access_token"] else 0
    logger.info("[Token] Token refreshed successfully - new_token_len: %s", new_token_len)

    return new_tokens["access_token"]

