from fastapi import APIRouter, HTTPException, Query
from modules.mercadolibre import get_valid_access_token
import requests

router = APIRouter(prefix="/ml", tags=["MercadoLibreProxy"])

ML_SITE_ID = "MLM"

BASE_HEADERS = {
    "Accept": "application/json",
    "Accept-Language": "es-MX,es;q=0.9,en;q=0.8",
    "User-Agent": "Mozilla/5.0",
    "Referer": "https://www.mercadolibre.com.mx/",
}

@router.get("/search")
def ml_search_proxy(
    q: str = Query(...),
    offset: int = 0,
    limit: int = 50,
    category: str | None = None,
    seller_id: str | None = None,
):
    token = get_valid_access_token()

    url = f"https://api.mercadolibre.com/sites/{ML_SITE_ID}/search"

    params = {
        "q": q,
        "offset": offset,
        "limit": limit,
    }
    if category:
        params["category"] = category
    if seller_id:
        params["seller_id"] = seller_id

    r = requests.get(
        url,
        params=params,
        headers={**BASE_HEADERS, "Authorization": f"Bearer {token}"},
        timeout=30,
    )

    if r.status_code >= 400:
        raise HTTPException(status_code=r.status_code, detail=r.text)

    return r.json()


@router.get("/items/{item_id}")
def ml_item_proxy(item_id: str):
    token = get_valid_access_token()

    url = f"https://api.mercadolibre.com/items/{item_id}"

    r = requests.get(
        url,
        headers={**BASE_HEADERS, "Authorization": f"Bearer {token}"},
        timeout=30,
    )

    if r.status_code >= 400:
        raise HTTPException(status_code=r.status_code, detail=r.text)

    return r.json()
