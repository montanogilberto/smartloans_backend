import os
import time
import base64
import logging
import requests

logger = logging.getLogger("ebay_auth")
logger.setLevel(logging.INFO)

_cache = {"token": None, "expires_at": 0}

def get_ebay_app_token() -> str:
    now = int(time.time())
    if _cache["token"] and now < (_cache["expires_at"] - 60):
        return _cache["token"]

    client_id = os.getenv("EBAY_CLIENT_ID")
    client_secret = os.getenv("EBAY_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise RuntimeError("Missing EBAY_CLIENT_ID/EBAY_CLIENT_SECRET")

    auth = base64.b64encode(f"{client_id}:{client_secret}".encode("utf-8")).decode("ascii")
    url = "https://api.ebay.com/identity/v1/oauth2/token"

    r = requests.post(
        url,
        headers={"Authorization": f"Basic {auth}", "Content-Type": "application/x-www-form-urlencoded"},
        data={"grant_type": "client_credentials", "scope": "https://api.ebay.com/oauth/api_scope"},
        timeout=30,
    )
    r.raise_for_status()
    j = r.json()

    _cache["token"] = j["access_token"]
    _cache["expires_at"] = now + int(j.get("expires_in", 7200))
    return _cache["token"]
