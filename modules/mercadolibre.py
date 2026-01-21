"""
modules/mercadolibre.py

Mercado Libre module:
- Save incoming webhook notifications to SQL (optional)
- Handle OAuth token exchange (authorization_code + PKCE)
"""

import os
import json
import logging
from typing import Any, Dict, Optional

import requests
from fastapi.responses import JSONResponse
from databases import connection

logger = logging.getLogger(__name__)

conn = connection()

# OAuth config (set these in Azure App Settings / local.settings.json)
ML_CLIENT_ID = os.getenv("ML_CLIENT_ID", "4763056577640918")
ML_CLIENT_SECRET = os.getenv("ML_CLIENT_SECRET", "t2SVlSDpNuB8YPM7VJFbvSCv4X1azuti")
ML_REDIRECT_URI = os.getenv(
    "ML_REDIRECT_URI",
    "https://smartloansbackend.azurewebsites.net/mercadolibre/oauth/callback"
)

# For PKCE: in a real app you store verifier per-user using state
# For now, simplest approach: env var
ML_CODE_VERIFIER = os.getenv("ML_CODE_VERIFIER", "")


def mercadolibre_webhook_sp(payload: dict) -> JSONResponse:
    """
    Save MercadoLibre webhook payload into DB (optional).

    Expected SP signature (example):
      EXEC dbo.sp_mercadolibre_webhook @pjsonfile = <json>

    IMPORTANT:
    - MercadoLibre expects HTTP 200 quickly; returning 200 avoids retries spam.
    """
    try:
        cursor = conn.cursor()

        pjson = json.dumps(payload, ensure_ascii=False)

        # If your driver is pyodbc, you probably must use "?" instead of "%s"
        # Example pyodbc:
        # cursor.execute("EXEC dbo.sp_mercadolibre_webhook ?", (pjson,))
        cursor.execute(
            "EXEC [dbo].[sp_mercadolibre_webhook] @pjsonfile = %s",
            (pjson,)
        )

        result = cursor.fetchall()

        # Safe output
        if result and len(result[0]) > 0:
            return JSONResponse(content={"ok": True, "db": result[0][0]}, status_code=200)

        return JSONResponse(content={"ok": True}, status_code=200)

    except Exception as e:
        logger.exception("mercadolibre_webhook_sp failed")
        # Keep 200 to avoid ML retry storms
        return JSONResponse(content={"ok": False, "error": str(e)}, status_code=200)


def exchange_code_for_token(
    *,
    code: str,
    code_verifier: Optional[str] = None
) -> Dict[str, Any]:
    """
    Exchange authorization code -> access token using PKCE.

    Returns token JSON dict on success.
    Raises Exception with detail on failure.
    """
    if not code:
        raise ValueError("Missing code")

    verifier = (code_verifier or ML_CODE_VERIFIER or "").strip()
    if not verifier:
        raise ValueError("Missing PKCE code_verifier (set ML_CODE_VERIFIER env var or pass it)")

    if not ML_CLIENT_SECRET:
        raise ValueError("Missing ML_CLIENT_SECRET environment variable")

    token_url = "https://api.mercadolibre.com/oauth/token"
    data = {
        "grant_type": "authorization_code",
        "client_id": ML_CLIENT_ID,
        "client_secret": ML_CLIENT_SECRET,
        "code": code,
        "redirect_uri": ML_REDIRECT_URI,
        "code_verifier": verifier,
    }

    r = requests.post(token_url, data=data, timeout=30)
    if r.status_code >= 400:
        raise RuntimeError(f"Token exchange failed: status={r.status_code} body={r.text}")

    return r.json()


def refresh_access_token(refresh_token: str) -> Dict[str, Any]:
    """
    Refresh access_token using refresh_token (PKCE not needed here).
    """
    if not refresh_token:
        raise ValueError("Missing refresh_token")

    if not ML_CLIENT_SECRET:
        raise ValueError("Missing ML_CLIENT_SECRET environment variable")

    token_url = "https://api.mercadolibre.com/oauth/token"
    data = {
        "grant_type": "refresh_token",
        "client_id": ML_CLIENT_ID,
        "client_secret": ML_CLIENT_SECRET,
        "refresh_token": refresh_token,
    }

    r = requests.post(token_url, data=data, timeout=30)
    if r.status_code >= 400:
        raise RuntimeError(f"Token refresh failed: status={r.status_code} body={r.text}")

    return r.json()
