"""
Provider-side usage for the Notifications screen ("Uso este mes" card).

Read-only. What each provider can actually tell us:

- Twilio (SMS, and WhatsApp before 2026-10-17): counted from the Messages API,
  grouped by the provider's own final status. NOT from Usage Records: those only
  count messages Twilio has priced, and October 2026 SMS stayed price=None while
  delivered (16 delivered, usage `sms-outbound` = 0), so the card read "0 enviados".
- Meta WhatsApp Cloud API: nothing to ask here. The per-message truth is our own
  dbo.notificationDispatches rows, which Meta's status webhooks
  (modules/whatsappCloud.py) move to confirmed/failed; the screen counts those.
  Meta's conversation analytics needs the WABA id and lags a day — not used.
- Push (Azure Notification Hub): only "accepted by the hub" exists; also counted
  by the screen from our rows.

Env:
  WHATSAPP_FREE_MONTHLY_LIMIT   optional int — free WhatsApp allowance / month the
                                screen measures against. Unset => limit is null.
  WA_SENDER_PHONE_NUMBER_ID     set => app WhatsApp goes out through Meta.
"""
import logging
import os
import time
from collections.abc import Iterable
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)

CACHE_SECONDS = 60
MAX_MESSAGES = 5000
_cache: Dict[str, Any] = {"at": 0.0, "payload": None}

# Same calendar the screen uses (America/Hermosillo, UTC-7, no DST).
HERMOSILLO = timezone(timedelta(hours=-7))

_DELIVERED = {"delivered", "read"}
_FAILED = {"failed", "undelivered", "canceled"}


def _twilio_client():
    from twilio.rest import Client
    sid, token = os.getenv("TWILIO_ACCOUNT_SID"), os.getenv("TWILIO_AUTH_TOKEN")
    if not sid or not token:
        raise ValueError("Missing Twilio credentials: TWILIO_ACCOUNT_SID and TWILIO_AUTH_TOKEN are required.")
    return Client(sid, token)


def _limit() -> int | None:
    raw = os.getenv("WHATSAPP_FREE_MONTHLY_LIMIT", "").strip()
    return int(raw) if raw.isdigit() and int(raw) > 0 else None


def month_start(now: datetime | None = None) -> datetime:
    """First instant of the current Hermosillo month, in UTC."""
    local = (now or datetime.now(timezone.utc)).astimezone(HERMOSILLO)
    return local.replace(day=1, hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)


def _empty() -> dict:
    return {"delivered": 0, "failed": 0, "inFlight": 0, "total": 0}


def count_messages(messages: Iterable) -> dict:
    """Pure: Twilio messages (anything with to/direction/status) -> outbound counts per channel.
    inFlight = accepted/queued/sent with no final receipt yet."""
    out = {"whatsapp": _empty(), "sms": _empty()}
    for m in messages:
        if not (m.direction or "").startswith("outbound"):
            continue
        bucket = out["whatsapp" if (m.to or "").startswith("whatsapp:") else "sms"]
        status = (m.status or "").lower()
        key = "delivered" if status in _DELIVERED else "failed" if status in _FAILED else "inFlight"
        bucket[key] += 1
        bucket["total"] += 1
    return out


def build_usage(twilio: dict, since: datetime) -> dict:
    """Pure: the API payload. `twilio` is count_messages(...) or {"ok": False, "error": ...}."""
    return {
        "ok": True,
        "period": "this_month",
        "since": since.isoformat().replace("+00:00", "Z"),
        "whatsappProvider": "meta" if os.getenv("WA_SENDER_PHONE_NUMBER_ID") else "none",
        "whatsappLimit": _limit(),
        "twilio": twilio if "ok" in twilio else {"ok": True, **twilio},
    }


def notification_usage() -> JSONResponse:
    now = time.monotonic()
    if _cache["payload"] is not None and now - _cache["at"] < CACHE_SECONDS:
        return JSONResponse(content=_cache["payload"], status_code=200)
    since = month_start()
    try:
        messages = _twilio_client().messages.list(date_sent_after=since, limit=MAX_MESSAGES, page_size=1000)
        twilio = count_messages(messages)
    except Exception as e:  # provider down / bad credentials: the rest of the card still works
        logger.warning("[notificationUsage] twilio messages unavailable: %s", e)
        twilio = {"ok": False, "error": "No se pudo consultar a Twilio."}
    payload = build_usage(twilio, since)
    if twilio.get("ok", True):
        _cache.update(at=now, payload=payload)
    return JSONResponse(content=payload, status_code=200)
