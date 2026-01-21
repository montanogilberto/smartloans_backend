from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, RedirectResponse

from modules.mercadolibre import (
    build_authorize_url,
    pop_code_verifier,
    exchange_code_for_token,
    upsert_tokens,
)

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
    return RedirectResponse(url=data["authorize_url"])

@router.get("/oauth/callback", summary="OAuth Callback (PKCE)")
def oauth_callback(code: str = "", state: str = ""):
    if not code or not state:
        return JSONResponse({"ok": False, "error": "Missing code/state"}, status_code=400)

    verifier = pop_code_verifier(state)
    if not verifier:
        return JSONResponse({"ok": False, "error": "Invalid/expired state"}, status_code=400)

    try:
        token_json = exchange_code_for_token(code, verifier)
        upsert_tokens(token_json)
        return JSONResponse({"ok": True, "saved": True})
    except Exception as e:
        return JSONResponse({"ok": False, "error": str(e)}, status_code=400)

@router.post("/webhook", summary="MercadoLibre Webhook")
async def webhook(request: Request):
    payload = await request.json()
    # store payload if you want; return 200 quickly
    return {"ok": True}
