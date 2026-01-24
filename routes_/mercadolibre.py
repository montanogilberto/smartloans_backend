import logging
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, RedirectResponse

from modules.mercadolibre import (
    build_authorize_url,
    pop_code_verifier,
    exchange_code_for_token,
    upsert_tokens,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/mercadolibre", tags=["MercadoLibre"])

@router.get("/ping", summary="Ping MercadoLibre")
def ping():
    return {"status": "ok", "service": "mercadolibre"}

@router.get("/oauth/authorize", summary="Start OAuth (redirect to ML)")
def oauth_authorize():
    """
    Generates state+pkce, stores it, and redirects to ML auth page.
    """
    data = build_authorize_url()
    logger.info("[OAuth] Starting authorization flow - state: %s...", data["state"][:8])
    return RedirectResponse(url=data["authorize_url"])

@router.get("/oauth/callback", summary="OAuth Callback (PKCE)")
def oauth_callback(code: str = "", state: str = ""):
    """
    OAuth callback handler with comprehensive debugging.
    Logs token saving details to help identify database mismatch issues.
    """
    logger.info("[OAuth] Callback received - code_len: %s, state: %s...",
               len(code) if code else 0, state[:8] if state else "None")

    if not code or not state:
        logger.error("[OAuth] Callback missing code or state")
        return JSONResponse({"ok": False, "error": "Missing code/state"}, status_code=400)

    verifier = pop_code_verifier(state)
    if not verifier:
        logger.error("[OAuth] Invalid or expired state: %s...", state[:8])
        return JSONResponse({"ok": False, "error": "Invalid/expired state"}, status_code=400)

    try:
        # Exchange code for tokens
        logger.info("[OAuth] Exchanging code for tokens...")
        token_json = exchange_code_for_token(code, verifier)

        # DEBUGGING: Log token details (masked)
        access_len = len(token_json.get("access_token", "")) if token_json.get("access_token") else 0
        refresh_len = len(token_json.get("refresh_token", "")) if token_json.get("refresh_token") else 0
        user_id = token_json.get("user_id", "N/A")
        expires_in = token_json.get("expires_in", "N/A")

        logger.info("[OAuth] Token exchange successful - user_id: %s, access_len: %s, refresh_len: %s, expires_in: %s",
                   user_id, access_len, refresh_len, expires_in)

        # Save tokens to database
        logger.info("[OAuth] Saving tokens to database...")
        upsert_tokens(token_json)

        logger.info("[OAuth] Tokens saved successfully - user_id: %s", user_id)
        return JSONResponse({"ok": True, "saved": True, "user_id": user_id})

    except Exception as e:
        logger.error("[OAuth] Token exchange or save failed: %s", str(e))
        return JSONResponse({"ok": False, "error": str(e)}, status_code=400)

@router.post("/webhook", summary="MercadoLibre Webhook")
async def webhook(request: Request):
    payload = await request.json()
    # store payload if you want; return 200 quickly
    return {"ok": True}

