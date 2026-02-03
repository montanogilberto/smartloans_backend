import logging
import secrets
from typing import Optional, Dict, Any

import requests
from fastapi import APIRouter, Query, Request, Depends, HTTPException
from fastapi.responses import JSONResponse

from security.worker_key import require_worker_key
from modules.ebay_auth import get_ebay_app_token

router = APIRouter(prefix="/ebay", tags=["EbayProxy"])
logger = logging.getLogger("ebay_proxy")
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

def _json_with_rid(rid: str, payload: Any, status_code: int = 200) -> JSONResponse:
    resp = JSONResponse(content=payload, status_code=status_code)
    resp.headers["x-request-id"] = rid
    return resp

def _is_invalid_token(resp: requests.Response) -> bool:
    # eBay invalid token is often 401/403 with specific error payload; keep simple:
    return resp.status_code in (401, 403)

@router.get("/search")
def ebay_search_proxy(
    request: Request,
    q: str = Query(...),
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    sort: Optional[str] = Query(None),  # e.g. newlyListed
    worker_ok=Depends(require_worker_key),
):
    rid = request.headers.get("x-request-id") or _req_id()

    marketplace = request.headers.get("x-ebay-marketplace") or "EBAY_US"
    url = "https://api.ebay.com/buy/browse/v1/item_summary/search"
    params: Dict[str, Any] = {"q": q, "offset": offset, "limit": limit}
    if sort:
        params["sort"] = sort

    try:
        token = get_ebay_app_token()
        headers = {
            "Accept": "application/json",
            "Authorization": f"Bearer {token}",
            "X-EBAY-C-MARKETPLACE-ID": marketplace,
        }

        logger.info("[%s] /ebay/search url=%s params=%s token=%s", rid, url, params, _mask_token(token))

        r = requests.get(url, params=params, headers=headers, timeout=30)
        _log_response(rid, "EBAY search WITH token", r)

        # Retry once if invalid/expired token
        if _is_invalid_token(r):
            logger.warning("[%s] EBAY token invalid -> retry once with new token", rid)
            token = get_ebay_app_token()  # refresh via cache logic
            headers["Authorization"] = f"Bearer {token}"
            r = requests.get(url, params=params, headers=headers, timeout=30)
            _log_response(rid, "EBAY search RETRY", r)

        if r.status_code >= 400:
            return _json_with_rid(rid, {"detail": r.text}, status_code=r.status_code)

        j = r.json()
        total = j.get("total")

        results = []
        for it in (j.get("itemSummaries") or []):
            price = it.get("price") or {}
            results.append({
                "id": it.get("itemId"),
                "title": it.get("title") or "",
                "price": float(price.get("value") or 0),
                "currency_id": price.get("currency") or "USD",
                "rating": None,
                "reviewsCount": None,
            })

        return _json_with_rid(
            rid,
            {
                "query": q,
                "paging": {"offset": offset, "limit": limit, "total": total},
                "results": results,
            },
            status_code=200,
        )

    except Exception as e:
        return _json_with_rid(rid, {"detail": str(e)}, status_code=500)
