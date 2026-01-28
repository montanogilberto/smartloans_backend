"""
routes_ml_proxy.py

Backend proxy for Mercado Libre API.
Workers call backend with X-Worker-Key, backend forwards to ML using OAuth token from DB.

Implemented endpoints:
- GET /ml/products/{product_id}/items   -> https://api.mercadolibre.com/products/{product_id}/items
- GET /ml/items?ids=MLM1,MLM2           -> https://api.mercadolibre.com/items?ids=...
- GET /ml/whoami                        -> https://api.mercadolibre.com/users/me  (debug)
- GET /ml/public_ping                   -> https://api.mercadolibre.com/currencies (debug)
"""

import logging
import secrets
from typing import Optional, Dict, Any

import requests
from fastapi import APIRouter, HTTPException, Query, Request, Depends
from fastapi.responses import JSONResponse

# ✅ worker-key dependency (ONLY workers can access protected routes)
from security.worker_key import require_worker_key

# ✅ your ML token helpers (already in your backend)
from modules.mercadolibre import (
    get_valid_access_token,
    get_latest_tokens,
    refresh_access_token,
    upsert_tokens,
)

router = APIRouter(prefix="/ml", tags=["MercadoLibreProxy"])
logger = logging.getLogger("ml_proxy")
logger.setLevel(logging.INFO)

ML_SITE_ID = "MLM"

# --------------------------
# Safe logging helpers
# --------------------------
def _req_id() -> str:
    return secrets.token_hex(6)

def _mask_token(token: str, keep: int = 6) -> str:
    if not token:
        return ""
    if len(token) <= keep:
        return "***"
    return token[:keep] + "..." + token[-3:]

def _log_response(rid: str, label: str, resp: requests.Response) -> None:
    body_preview = (resp.text or "")[:1200]
    logger.info("[%s] %s status=%s", rid, label, resp.status_code)
    logger.info("[%s] %s body_preview=%s", rid, label, body_preview)

def _is_invalid_token(resp: requests.Response) -> bool:
    if resp.status_code != 401:
        return False
    try:
        j = resp.json() if resp.content else {}
    except Exception:
        j = {}
    msg = (j.get("message") or "").lower()
    err = (j.get("error") or "").lower()
    return ("invalid" in msg and "token" in msg) or (err == "invalid_token")

def _refresh_and_get_new_access_token(rid: str) -> Optional[str]:
    tokens = get_latest_tokens()
    if not tokens:
        logger.error("[%s] No tokens in DB to refresh", rid)
        return None
    try:
        new_tokens = refresh_access_token(tokens["refresh_token"])
        upsert_tokens(new_tokens)
        return new_tokens.get("access_token")
    except Exception as e:
        logger.error("[%s] Token refresh failed: %s", rid, str(e))
        return None

def _json_with_rid(rid: str, payload: Any, status_code: int = 200) -> JSONResponse:
    resp = JSONResponse(content=payload, status_code=status_code)
    resp.headers["x-request-id"] = rid
    return resp

# --------------------------
# Browser-like headers
# --------------------------
BROWSER_HEADERS: Dict[str, str] = {
    "Accept": "application/json",
    "Accept-Language": "es-MX,es;q=0.9,en;q=0.8",
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Referer": "https://www.mercadolibre.com.mx/",
    "Origin": "https://www.mercadolibre.com.mx",
}

# ============================================================
# ✅ WORKER-ONLY: product unify -> items
# GET /ml/products/{product_id}/items
# ============================================================
@router.get("/products/{product_id}/items")
def ml_product_items_proxy(
    request: Request,
    product_id: str,
    offset: int = 0,
    limit: int = 50,
    _: str = Depends(require_worker_key),
):
    rid = request.headers.get("x-request-id") or _req_id()

    try:
        token = get_valid_access_token()
    except Exception as token_err:
        logger.error("[%s] Token retrieval failed: %s", rid, str(token_err))
        raise HTTPException(status_code=500, detail=f"Token retrieval failed: {str(token_err)}")

    url = f"https://api.mercadolibre.com/products/{product_id}/items"
    params: Dict[str, Any] = {"offset": offset, "limit": limit}
    headers = {**BROWSER_HEADERS, "Authorization": f"Bearer {token}"}

    logger.info("[%s] /products/%s/items params=%s token=%s", rid, product_id, params, _mask_token(token))

    r = requests.get(url, params=params, headers=headers, timeout=30)
    _log_response(rid, "ML products/items", r)

    if _is_invalid_token(r):
        logger.warning("[%s] invalid_token -> refresh and retry once", rid)
        new_access = _refresh_and_get_new_access_token(rid)
        if new_access:
            headers["Authorization"] = f"Bearer {new_access}"
            r = requests.get(url, params=params, headers=headers, timeout=30)
            _log_response(rid, "ML products/items RETRY", r)

    if r.status_code >= 400:
        return _json_with_rid(rid, {"detail": r.text}, status_code=r.status_code)

    return _json_with_rid(rid, r.json(), status_code=200)

# ============================================================
# ✅ WORKER-ONLY: BULK items endpoint
# GET /ml/items?ids=MLM1,MLM2
# ============================================================
@router.get("/items")
def ml_items_bulk_proxy(
    request: Request,
    ids: str = Query(..., description="Comma-separated item ids: MLM123,MLM456"),
    _: str = Depends(require_worker_key),
):
    rid = request.headers.get("x-request-id") or _req_id()

    try:
        token = get_valid_access_token()
    except Exception as token_err:
        logger.error("[%s] Token retrieval failed: %s", rid, str(token_err))
        raise HTTPException(status_code=500, detail=f"Token retrieval failed: {str(token_err)}")

    url = "https://api.mercadolibre.com/items"
    params = {"ids": ids}
    headers = {**BROWSER_HEADERS, "Authorization": f"Bearer {token}"}

    logger.info("[%s] /items bulk ids_len=%s token=%s", rid, len(ids), _mask_token(token))

    r = requests.get(url, params=params, headers=headers, timeout=30)
    _log_response(rid, "ML items BULK", r)

    if _is_invalid_token(r):
        logger.warning("[%s] invalid_token -> refresh and retry once", rid)
        new_access = _refresh_and_get_new_access_token(rid)
        if new_access:
            headers["Authorization"] = f"Bearer {new_access}"
            r = requests.get(url, params=params, headers=headers, timeout=30)
            _log_response(rid, "ML items BULK RETRY", r)

    if r.status_code >= 400:
        return _json_with_rid(rid, {"detail": r.text}, status_code=r.status_code)

    return _json_with_rid(rid, r.json(), status_code=200)

# ============================================================
# Debug: whoami (public or protect—tú decides)
# ============================================================
@router.get("/whoami")
def ml_whoami(request: Request):
    rid = request.headers.get("x-request-id") or _req_id()

    try:
        token = get_valid_access_token()
    except Exception as token_err:
        raise HTTPException(status_code=500, detail=f"Token retrieval failed: {str(token_err)}")

    url = "https://api.mercadolibre.com/users/me"
    headers = {"Authorization": f"Bearer {token}"}

    r = requests.get(url, headers=headers, timeout=30)
    _log_response(rid, "ML users/me", r)

    if r.status_code >= 400:
        return _json_with_rid(rid, {"detail": r.text}, status_code=r.status_code)

    return _json_with_rid(rid, r.json(), status_code=200)

# ============================================================
# Debug: public ping
# ============================================================
@router.get("/public_ping")
def public_ping(request: Request):
    rid = request.headers.get("x-request-id") or _req_id()
    r = requests.get("https://api.mercadolibre.com/currencies", timeout=15)

    payload = {
        "status": r.status_code,
        "headers": {
            "x-policy-agent-block-code": r.headers.get("x-policy-agent-block-code"),
            "x-policy-agent-block-reason": r.headers.get("x-policy-agent-block-reason"),
            "via": r.headers.get("via"),
            "x-cache": r.headers.get("x-cache"),
            "x-amz-cf-pop": r.headers.get("x-amz-cf-pop"),
        },
        "body_preview": (r.text or "")[:200],
    }
    return _json_with_rid(rid, payload, status_code=200)
