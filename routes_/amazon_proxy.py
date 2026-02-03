import logging
import secrets
from typing import Optional, Dict, Any

import requests
from fastapi import APIRouter, HTTPException, Query, Request, Depends
from fastapi.responses import JSONResponse

from security.worker_key import require_worker_key

# If using SP-API:
# from modules.amazon_spapi import amz_get_valid_access_token, amz_refresh_access_token, amz_get_latest_tokens, amz_upsert_tokens

router = APIRouter(prefix="/amazon", tags=["AmazonProxy"])
logger = logging.getLogger("amazon_proxy")
logger.setLevel(logging.INFO)

# --------------------------
# Logging (safe)
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
    logger.info("[%s] %s resp_headers=%s", rid, label, dict(resp.headers))

def _json_with_rid(rid: str, payload: Any, status_code: int = 200) -> JSONResponse:
    resp = JSONResponse(content=payload, status_code=status_code)
    resp.headers["x-request-id"] = rid
    return resp

# --------------------------
# Browser-like headers (useful for SERP providers / web-like endpoints)
# --------------------------
BROWSER_HEADERS: Dict[str, str] = {
    "Accept": "application/json",
    "Accept-Language": "en-US,en;q=0.9",
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
}

# --------------------------
# Endpoint
# --------------------------
@router.get("/search")
def amazon_search_proxy(
    request: Request,
    q: str = Query(...),
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=1000),
    sort: Optional[str] = Query(None),
    worker_ok=Depends(require_worker_key),
):
    """
    Standard contract for workers:
    {
      "query": "...",
      "paging": {"offset":0,"limit":50,"total":null},
      "results": [{"id":"ASIN","title":"...","price":123.45,"currency_id":"USD","rating":4.6,"reviewsCount":120}]
    }
    """
    rid = request.headers.get("x-request-id") or _req_id()

    mode = (request.headers.get("x-amazon-mode") or "serp").lower()
    # You can also use env var:
    # mode = (os.getenv("AMZ_MODE") or "serp").lower()

    try:
        # ---------------------------------------
        # MODE A: SERP / DATA PROVIDER
        # ---------------------------------------
        if mode == "serp":
            # Example: call your provider endpoint (replace with real provider)
            # url = "https://your-serp-provider/search"
            # headers = {**BROWSER_HEADERS, "X-API-KEY": os.getenv("AMZ_SERP_API_KEY")}
            # params = {"q": q, "offset": offset, "limit": limit, "sort": sort}
            # r = requests.get(url, params=params, headers=headers, timeout=30)

            # Placeholder response (keep contract stable)
            logger.info("[%s] amazon/search SERP q=%s offset=%s limit=%s", rid, q, offset, limit)
            return _json_with_rid(rid, {"query": q, "paging": {"offset": offset, "limit": limit, "total": None}, "results": []}, 200)

        # ---------------------------------------
        # MODE B: SP-API (Official)
        # ---------------------------------------
        if mode == "spapi":
            # This depends on your implementation.
            # Typically:
            # token = amz_get_valid_access_token()
            # headers = {"Authorization": f"Bearer {token}", ...signing...}
            # r = requests.get(spapi_url, headers=headers, params=..., timeout=30)
            # _log_response(...)
            #
            # If token invalid => refresh and retry once
            #
            # Normalize response to results[]
            logger.info("[%s] amazon/search SPAPI q=%s offset=%s limit=%s", rid, q, offset, limit)
            return _json_with_rid(rid, {"query": q, "paging": {"offset": offset, "limit": limit, "total": None}, "results": []}, 200)

        raise HTTPException(status_code=400, detail=f"Invalid amazon mode: {mode}")

    except HTTPException:
        raise
    except Exception as e:
        return _json_with_rid(rid, {"detail": str(e)}, status_code=500)
