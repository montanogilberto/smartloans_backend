"""
routes_/ml_proxy.py

MINIMAL CHANGE:
- If ML returns 401 invalid_token, refresh token and retry ONCE.
"""

import logging
import secrets
from typing import Optional, Dict, Any

import requests
from fastapi import APIRouter, HTTPException, Query
from modules.mercadolibre import (
    get_valid_access_token,
    get_latest_tokens,
    refresh_access_token,
    upsert_tokens,
)

ml_router = APIRouter(prefix="/ml", tags=["MercadoLibreProxy"])

ML_SITE_ID = "MLM"

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
    logger.info("[%s] %s resp_headers=%s", rid, label, dict(resp.headers))


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


@ml_router.get("/search")
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

    try:
        token = get_valid_access_token()
    except Exception as token_err:
        raise HTTPException(status_code=500, detail=f"Token retrieval failed: {str(token_err)}")

    headers_with_token = {**BROWSER_HEADERS, "Authorization": f"Bearer {token}"}
    logger.info("[%s] /ml/search url=%s params=%s token=%s", rid, url, params, _mask_token(token))

    r = requests.get(url, params=params, headers=headers_with_token, timeout=30)
    _log_response(rid, "ML search WITH token", r)

    # NEW: invalid_token -> refresh and retry once
    if _is_invalid_token(r):
        logger.warning("[%s] 401 invalid_token on /search -> refresh and retry once", rid)
        new_access = _refresh_and_get_new_access_token(rid)
        if new_access:
            headers_with_token["Authorization"] = f"Bearer {new_access}"
            r = requests.get(url, params=params, headers=headers_with_token, timeout=30)
            _log_response(rid, "ML search RETRY after refresh", r)

    # Keep: 403 with token -> retry without token
    if r.status_code == 403:
        logger.warning("[%s] 403 WITH token -> retry WITHOUT token", rid)
        r2 = requests.get(url, params=params, headers=BROWSER_HEADERS, timeout=30)
        _log_response(rid, "ML search WITHOUT token", r2)
        r = r2

    if r.status_code >= 400:
        raise HTTPException(status_code=r.status_code, detail=r.text)

    return r.json()


@ml_router.get("/items/{item_id}")
def ml_item_proxy(item_id: str):
    rid = _req_id()
    url = f"https://api.mercadolibre.com/items/{item_id}"

    try:
        token = get_valid_access_token()
    except Exception as token_err:
        raise HTTPException(status_code=500, detail=f"Token retrieval failed: {str(token_err)}")

    headers = {**BROWSER_HEADERS, "Authorization": f"Bearer {token}"}
    r = requests.get(url, headers=headers, timeout=30)
    _log_response(rid, "ML item WITH token", r)

    if _is_invalid_token(r):
        logger.warning("[%s] 401 invalid_token on /items -> refresh and retry once", rid)
        new_access = _refresh_and_get_new_access_token(rid)
        if new_access:
            headers["Authorization"] = f"Bearer {new_access}"
            r = requests.get(url, headers=headers, timeout=30)
            _log_response(rid, "ML item RETRY after refresh", r)

    if r.status_code >= 400:
        raise HTTPException(status_code=r.status_code, detail=r.text)

    return r.json()


@ml_router.get("/whoami")
def ml_whoami():
    rid = _req_id()
    url = "https://api.mercadolibre.com/users/me"

    try:
        token = get_valid_access_token()
    except Exception as token_err:
        raise HTTPException(status_code=500, detail=f"Token retrieval failed: {str(token_err)}")

    headers = {"Authorization": f"Bearer {token}"}
    r = requests.get(url, headers=headers, timeout=30)
    _log_response(rid, "ML users/me", r)

    if _is_invalid_token(r):
        logger.warning("[%s] 401 invalid_token on /whoami -> refresh and retry once", rid)
        new_access = _refresh_and_get_new_access_token(rid)
        if new_access:
            headers["Authorization"] = f"Bearer {new_access}"
            r = requests.get(url, headers=headers, timeout=30)
            _log_response(rid, "ML users/me RETRY after refresh", r)

    if r.status_code >= 400:
        raise HTTPException(status_code=r.status_code, detail=r.text)

    return r.json()


@ml_router.get("/public_ping")
def public_ping():
    r = requests.get("https://api.mercadolibre.com/currencies", timeout=15)
    return {"status": r.status_code, "body_preview": r.text[:200]}
