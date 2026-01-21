"""
routes_/mercadolibre.py

FastAPI routes for Mercado Libre:
- GET  /mercadolibre/ping
- POST /mercadolibre/webhook     (notifications webhook)
- GET  /mercadolibre/oauth/callback  (OAuth redirect URI)
"""

from fastapi import APIRouter, Request, Query
from fastapi.responses import JSONResponse, HTMLResponse

from modules.mercadolibre import (
    mercadolibre_webhook_sp,
    exchange_code_for_token,
)

router = APIRouter(prefix="/mercadolibre", tags=["MercadoLibre"])


@router.get("/ping", summary="Ping MercadoLibre")
def ping():
    return {"status": "ok", "service": "mercadolibre"}


@router.post("/webhook", summary="MercadoLibre Notifications Webhook")
async def webhook(request: Request):
    """
    This endpoint is for MercadoLibre notifications (POST JSON).
    MercadoLibre sends a JSON body here when events occur.
    """
    try:
        payload = await request.json()
    except Exception:
        # If ML sends non-json for some reason, still return 200
        return JSONResponse(content={"ok": False, "error": "Invalid JSON"}, status_code=200)

    # Save into DB (optional)
    return mercadolibre_webhook_sp(payload)


@router.get("/oauth/callback", summary="MercadoLibre OAuth Callback (PKCE)")
def oauth_callback(
    code: str = Query(default=None),
    state: str = Query(default=None),
    error: str = Query(default=None),
    error_description: str = Query(default=None),
):
    """
    This endpoint is the Redirect URI for OAuth.
    MercadoLibre redirects with:
      GET /mercadolibre/oauth/callback?code=...&state=...
    or on error:
      GET ...?error=...&error_description=...
    """
    if error:
        # Still 200 for user-friendly result
        return JSONResponse(
            status_code=200,
            content={
                "ok": False,
                "error": error,
                "error_description": error_description,
                "state": state,
            },
        )

    if not code:
        return JSONResponse(status_code=400, content={"ok": False, "error": "Missing code"})

    try:
        token_json = exchange_code_for_token(code=code)

        # ✅ TODO: store securely (DB / KeyVault) instead of returning
        # For security, we do NOT return tokens by default.
        # If you want to debug, temporarily return token_json.

        return HTMLResponse(
            content="""
              <h3>OK ✅ Mercado Libre autorizado.</h3>
              <p>Ya puedes cerrar esta ventana.</p>
            """,
            status_code=200,
        )

    except Exception as e:
        # Return 200 so the browser shows a helpful message
        return JSONResponse(status_code=200, content={"ok": False, "error": str(e), "state": state})
