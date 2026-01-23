"""
modules/mercadolibre.py

Dynamic PKCE OAuth for Mercado Libre:
- Generate authorize URL with PKCE + state
- Persist state -> code_verifier
- Callback exchanges code -> tokens
- Store tokens and auto-refresh
"""

import os
import logging
import base64
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional, Tuple

import requests
from databases import connection

logger = logging.getLogger(__name__)

ML_CLIENT_ID = os.getenv("ML_CLIENT_ID", "").strip()
ML_CLIENT_SECRET = os.getenv("ML_CLIENT_SECRET", "").strip()
ML_REDIRECT_URI = os.getenv("ML_REDIRECT_URI", "").strip()

AUTH_URL = "https://auth.mercadolibre.com.mx/authorization"
TOKEN_URL = "https://api.mercadolibre.com/oauth/token"

logger.info("ML_CLIENT_ID loaded? %s", bool(ML_CLIENT_ID))
logger.info("ML_REDIRECT_URI loaded? %s", bool(ML_REDIRECT_URI))
logger.info("ML_CLIENT_SECRET loaded? %s", bool(ML_CLIENT_SECRET))


def _get_conn():
    """
    Always returns a fresh DB connection.
    Avoids stale connections in Azure / FastAPI.
    """
    return connection()


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("utf-8")


def generate_pkce_pair() -> Tuple[str, str]:
    """Returns (code_verifier, code_challenge)."""
    verifier = _b64url(secrets.token_bytes(32))
    challenge = _b64url(hashlib.sha256(verifier.encode("utf-8")).digest())
    return verifier, challenge


def save_oauth_state(state: str, code_verifier: str) -> None:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO dbo.ml_oauth_states (state, code_verifier)
            VALUES (%s, %s)
            """,
            (state, code_verifier),
        )
        conn.commit()
        logger.info("[DB] OAuth state saved - state: %s...", state[:8])
    finally:
        conn.close()


def pop_code_verifier(state: str) -> Optional[str]:
    """
    Reads verifier and marks state as used.
    Minimal approach; if you want perfect atomicity, we can do an UPDATE...OUTPUT pattern.
    """
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT code_verifier
            FROM dbo.ml_oauth_states
            WHERE state = %s AND used_at IS NULL
            """,
            (state,),
        )
        row = cur.fetchone()
        if not row:
            logger.warning("[DB] No code_verifier found for state: %s", state[:8])
            return None

        verifier = row[0]

        cur.execute(
            """
            UPDATE dbo.ml_oauth_states
            SET used_at = SYSUTCDATETIME()
            WHERE state = %s AND used_at IS NULL
            """,
            (state,),
        )
        conn.commit()

        logger.info("[DB] Code verifier retrieved and marked used - state: %s...", state[:8])
        return verifier
    finally:
        conn.close()


def upsert_tokens(token_json: Dict[str, Any]) -> None:
    access_token = token_json["access_token"]
    refresh_token = token_json["refresh_token"]
    expires_in = int(token_json.get("expires_in", 21600))
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=expires_in - 60)

    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute("SELECT TOP 1 id FROM dbo.ml_tokens ORDER BY id DESC")
        row = cur.fetchone()

        if row:
            token_id = row[0]
            cur.execute(
                """
                UPDATE dbo.ml_tokens
                SET access_token = %s,
                    refresh_token = %s,
                    expires_at = %s,
                    updated_at = SYSUTCDATETIME()
                WHERE id = %s
                """,
                (access_token, refresh_token, expires_at, token_id),
            )
            conn.commit()
            logger.info("[DB] Tokens updated - token_id: %s", token_id)
        else:
            cur.execute(
                """
                INSERT INTO dbo.ml_tokens (access_token, refresh_token, expires_at)
                VALUES (%s, %s, %s)
                """,
                (access_token, refresh_token, expires_at),
            )
            conn.commit()
            logger.info("[DB] Tokens inserted")
    finally:
        conn.close()


def get_latest_tokens() -> Optional[Dict[str, Any]]:
    conn = _get_conn()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT TOP 1 access_token, refresh_token, expires_at
            FROM dbo.ml_tokens
            ORDER BY id DESC
            """
        )
        row = cur.fetchone()
        if not row:
            logger.warning("[DB] No tokens found in database")
            return None

        return {"access_token": row[0], "refresh_token": row[1], "expires_at": row[2]}
    finally:
        conn.close()


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
    return {"authorize_url": authorize_url, "state": state}


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

    r = requests.post(TOKEN_URL, data=payload, timeout=30)
    if r.status_code >= 400:
        raise RuntimeError(f"Token exchange failed ({r.status_code}): {r.text}")
    return r.json()


def refresh_access_token(refresh_token: str) -> Dict[str, Any]:
    payload = {
        "grant_type": "refresh_token",
        "client_id": ML_CLIENT_ID,
        "client_secret": ML_CLIENT_SECRET,
        "refresh_token": refresh_token,
    }

    r = requests.post(TOKEN_URL, data=payload, timeout=30)
    if r.status_code >= 400:
        raise RuntimeError(f"Token refresh failed ({r.status_code}): {r.text}")
    return r.json()


def get_valid_access_token() -> str:
    """
    Workers/backend call this.
    Returns a valid access_token.
    """
    tokens = get_latest_tokens()
    if not tokens:
        raise RuntimeError("No Mercado Libre tokens found. Run OAuth flow first.")

    expires_at = tokens["expires_at"]
    now = datetime.now(timezone.utc)

    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)

    if now < expires_at:
        return tokens["access_token"]

    new_tokens = refresh_access_token(tokens["refresh_token"])
    upsert_tokens(new_tokens)
    return new_tokens["access_token"]
