"""
routes_/ml_proxy.py

MercadoLibre proxy endpoints:
- /ml/search  -> calls ML sites search
- /ml/items/* -> calls ML item detail
Uses your DB-stored OAuth token via get_valid_access_token()
Adds safe logging (no secrets) + request-id tracing
"""

import logging
import secrets
from typing import Optional, Dict, Any

import requests
from fastapi import APIRouter, HTTPException, Query
from modules.mercadolibre import get_valid_access_token

router = APIRouter(prefix="/ml", tags=["MercadoLibreProxy"])

ML_SITE_ID = "MLM"

# --------------------------
# Logging (safe)
# --------------------------
logger = logging.getLogger("ml_proxy")
logger.setLevel(logging.INFO)

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
    # Sometimes ML sends useful headers (rate limits, request ids, etc.)
    logger.info("[%s] %s resp_headers=%s", rid, label, dict(resp.headers))

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

# --------------------------
# Endpoints
# --------------------------
@router.get("/search")
def ml_search_proxy(
    q: str = Query(...),
    offset: int = 0,
    limit: int = 50,
    category: Optional[str] = None,
    seller_id: Optional[str] = None,
):
    rid = _req_id()

    url = f"https://api.mercadolibre.com/sites/{ML_SITE_ID}/search"
    params: Dict[str, Any] = {"q": q, "offset": offset, "limit": limit}
    if category:
        params["category"] = category
    if seller_id:
        params["seller_id"] = seller_id

    # ================================================
    # DEBUGGING: Check token presence and headers
    # ================================================
    try:
        token = get_valid_access_token()
        logger.info("[%s] TOKEN present: %s, len: %s", 
                   rid, bool(token), len(token) if token else 0)
    except Exception as token_err:
        logger.error("[%s] Failed to get access token: %s", rid, str(token_err))
        raise HTTPException(status_code=500, detail=f"Token retrieval failed: {str(token_err)}")
    
    # Prepare headers
    headers_with_token = {**BROWSER_HEADERS, "Authorization": f"Bearer {token}"}
    
    # DEBUGGING: Log header details (safe, no secrets)
    logger.info("[%s] Has Authorization: %s", rid, "Authorization" in headers_with_token)
    logger.info("[%s] UA: %s", rid, headers_with_token.get("User-Agent"))
    logger.info("[%s] All headers keys: %s", rid, list(headers_with_token.keys()))
    
    # Log request details
    logger.info("[%s] /ml/search url=%s params=%s token=%s", 
               rid, url, params, _mask_token(token))

    # ================================================
    # Try WITH token
    # ================================================
    r = requests.get(url, params=params, headers=headers_with_token, timeout=30)
    _log_response(rid, "ML search WITH token", r)

    # ================================================
    # Diagnostic: if ML forbids when you include token, retry WITHOUT token
    # (This endpoint is often public; sometimes token triggers stricter rules)
    # ================================================
    if r.status_code == 403:
        logger.warning("[%s] 403 WITH token -> retry WITHOUT token", rid)
        logger.info("[%s] Token was present: %s, Authorization header: %s", 
                   rid, bool(token), "Authorization" in headers_with_token)
        
        r2 = requests.get(url, params=params, headers=BROWSER_HEADERS, timeout=30)
        _log_response(rid, "ML search WITHOUT token", r2)
        r = r2

    if r.status_code >= 400:
        raise HTTPException(status_code=r.status_code, detail=r.text)

    return r.json()


@router.get("/items/{item_id}")
def ml_item_proxy(item_id: str):
    rid = _req_id()

    url = f"https://api.mercadolibre.com/items/{item_id}"

    # ================================================
    # DEBUGGING: Check token presence and headers
    # ================================================
    try:
        token = get_valid_access_token()
        logger.info("[%s] TOKEN present: %s, len: %s", 
                   rid, bool(token), len(token) if token else 0)
    except Exception as token_err:
        logger.error("[%s] Failed to get access token: %s", rid, str(token_err))
        raise HTTPException(status_code=500, detail=f"Token retrieval failed: {str(token_err)}")

    logger.info("[%s] /ml/items/%s url=%s token=%s", rid, item_id, url, _mask_token(token))

    headers = {**BROWSER_HEADERS, "Authorization": f"Bearer {token}"}
    
    # DEBUGGING: Log header details
    logger.info("[%s] Has Authorization: %s", rid, "Authorization" in headers)
    logger.info("[%s] UA: %s", rid, headers.get("User-Agent"))

    r = requests.get(url, headers=headers, timeout=30)
    _log_response(rid, "ML item WITH token", r)

    if r.status_code >= 400:
        raise HTTPException(status_code=r.status_code, detail=r.text)

    return r.json()


@router.get("/whoami")
def ml_whoami():
    """
    Debug endpoint to confirm token validity.
    If this returns 200 but /search returns 403, it's endpoint-specific behavior/WAF.
    """
    rid = _req_id()

    # ================================================
    # DEBUGGING: Check token presence and headers
    # ================================================
    try:
        token = get_valid_access_token()
        logger.info("[%s] TOKEN present: %s, len: %s", 
                   rid, bool(token), len(token) if token else 0)
    except Exception as token_err:
        logger.error("[%s] Failed to get access token: %s", rid, str(token_err))
        raise HTTPException(status_code=500, detail=f"Token retrieval failed: {str(token_err)}")

    url = "https://api.mercadolibre.com/users/me"
    logger.info("[%s] /ml/whoami url=%s token=%s", rid, url, _mask_token(token))

    headers = {"Authorization": f"Bearer {token}"}
    
    # DEBUGGING: Log header details
    logger.info("[%s] Has Authorization: %s", rid, "Authorization" in headers)
    
    r = requests.get(url, headers=headers, timeout=30)
    _log_response(rid, "ML users/me", r)

    if r.status_code >= 400:
        raise HTTPException(status_code=r.status_code, detail=r.text)

    return r.json()

