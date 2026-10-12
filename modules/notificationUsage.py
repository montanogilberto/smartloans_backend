"""
Provider-side WhatsApp / SMS usage for the Notifications screen.

Read-only. The numbers come from Twilio's Usage Records API (what the provider
actually carried and billed this month), NOT from dbo.notificationDispatches:
our table records that a send was *accepted* ('sent'), and the provider can
still fail it afterwards (e.g. income #4863, 2026-10-02: ours says sent, Twilio
usage says 0 outbound WhatsApp). The screen shows both so the gap is visible.

Not covered: WhatsApp messages sent straight through Meta's Cloud API
(modules/whatsappCloud.py) never touch Twilio and do not appear here — Meta's
own analytics (needs the WABA id) is the source for those.

Env:
  WHATSAPP_FREE_MONTHLY_LIMIT   optional int — the free allowance to measure
                                against (outbound WhatsApp messages / month).
                                Unset => no `limit`/`remaining` are reported;
                                the real number is in the Meta/Twilio account.
"""
import logging
import os
import time
from typing import Any, Dict

from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)

CACHE_SECONDS = 60
_cache: Dict[str, Any] = {"at": 0.0, "payload": None}

_CATEGORY_KEYS = {
    "channels-whatsapp-outbound": "outboundMessages",
    "channels-whatsapp-inbound": "inboundMessages",
    "channels-whatsapp": "conversations",
    "channels-whatsapp-conversation-free": "freeConversations",
    "sms-outbound": "smsOutboundMessages",
}


def _twilio_client():
    from twilio.rest import Client
    sid, token = os.getenv("TWILIO_ACCOUNT_SID"), os.getenv("TWILIO_AUTH_TOKEN")
    if not sid or not token:
        raise ValueError("Missing Twilio credentials: TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN are required.")
    return Client(sid, token)


def _limit() -> int | None:
    raw = os.getenv("WHATSAPP_FREE_MONTHLY_LIMIT", "").strip()
    return int(raw) if raw.isdigit() and int(raw) > 0 else None


def build_usage(records) -> dict:
    """Pure: Twilio usage records (anything with category/count/price/price_unit) -> the API payload."""
    values = {key: 0 for key in _CATEGORY_KEYS.values()}
    price, price_unit = 0.0, "usd"
    for record in records:
        key = _CATEGORY_KEYS.get(record.category)
        if key:
            values[key] = int(float(record.count or 0))
        if record.category == "channels-whatsapp":
            price = float(record.price or 0)
            price_unit = record.price_unit or price_unit

    whatsapp = {
        "outboundMessages": values["outboundMessages"],
        "inboundMessages": values["inboundMessages"],
        "conversations": values["conversations"],
        "freeConversations": values["freeConversations"],
        "billableConversations": max(values["conversations"] - values["freeConversations"], 0),
        "price": price,
        "priceUnit": price_unit,
        "limit": None,
        "remaining": None,
    }
    limit = _limit()
    if limit is not None:
        whatsapp["limit"] = limit
        whatsapp["remaining"] = max(limit - whatsapp["outboundMessages"], 0)
    return {
        "ok": True,
        "source": "twilio",
        "period": "this_month",
        "whatsapp": whatsapp,
        "sms": {"outboundMessages": values["smsOutboundMessages"]},
    }


def notification_usage() -> JSONResponse:
    now = time.monotonic()
    if _cache["payload"] is not None and now - _cache["at"] < CACHE_SECONDS:
        return JSONResponse(content=_cache["payload"], status_code=200)
    try:
        payload = build_usage(_twilio_client().usage.records.this_month.list())
    except Exception as e:  # provider down / bad credentials: the screen degrades to our own counts
        logger.warning("[notificationUsage] provider usage unavailable: %s", e)
        return JSONResponse(content={"ok": False, "error": "No se pudo consultar el uso del proveedor."}, status_code=200)
    _cache.update(at=now, payload=payload)
    return JSONResponse(content=payload, status_code=200)
