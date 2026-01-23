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

oauth_router = APIRouter(prefix="/mercadolibre", tags=["MercadoLibre"])


@oauth_router.get("/ping", summary="Ping MercadoLibre")
def ping():
    return {"status": "ok", "service": "mercadolibre"}


@oauth_router.get("/oauth/authorize", summary="Start OAuth (redirect to ML)")
def oauth_authorize():
    data = build_authorize_url()
    logger.info("[OAuth] Starting authorization flow - state: %s...", data["state"][:8])
    return RedirectResponse(url=data["authorize_url"])


@oauth_router.get("/oauth/callback", summary="OAuth Callback (PKCE)")
def oauth_callback(code: str = "", state: str = ""):
    logger.info("[OAuth] Callback received - code_len: %s, state: %s...",
                len(code) if code else 0, state[:8] if state else "None")

    if not code or not state:
        return JSONResponse({"ok": False, "error": "Missing code/state"}, status_code=400)

    verifier = pop_code_verifier(state)
    if not verifier:
        return JSONResponse({"ok": False, "error": "Invalid/expired state"}, status_code=400)

    try:
        token_json = exchange_code_for_token(code, verifier)
        upsert_tokens(token_json)
        return JSONResponse({"ok": True, "saved": True, "user_id": token_json.get("user_id")})
    except Exception as e:
        logger.error("[OAuth] Token exchange or save failed: %s", str(e))
        return JSONResponse({"ok": False, "error": str(e)}, status_code=400)


@oauth_router.post("/webhook", summary="MercadoLibre Webhook")
async def webhook(request: Request):
    _ = await request.json()
    return {"ok": True}
