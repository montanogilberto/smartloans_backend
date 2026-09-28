"""
WhatsApp numbers → company/branch (sp_whatsappChannels) and the bot's
per-chat state (sp_whatsappConversations). One number per branch; Meta's
webhook tells us which number a message arrived on (phone_number_id).

Channel lookups are cached in-process for CHANNEL_CACHE_SECONDS — every
inbound message needs one, and numbers change rarely. Conversation state is
NOT cached: it must be the same on every App Service instance.
"""

import json
import logging
import os
import time
from typing import Optional

from fastapi.responses import JSONResponse

from databases import connection

logger = logging.getLogger(__name__)

CHANNEL_CACHE_SECONDS = 300

# phoneNumberId -> (expiresAt, channel dict or None)
_channel_cache: dict[str, tuple[float, Optional[dict]]] = {}


def _sp(procedure: str, json_file: dict) -> dict:
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{procedure}] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        conn.commit()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


# ── Channels ────────────────────────────────────────────────────────────────

def get_channel(phone_number_id: str) -> Optional[dict]:
    """Active channel for a Meta phone_number_id, or None if the number isn't
    registered. Unknown numbers are cached too, so a misconfigured number
    doesn't hit the DB on every message."""
    if not phone_number_id:
        return None
    cached = _channel_cache.get(phone_number_id)
    if cached and cached[0] > time.time():
        return cached[1]

    result = _sp("sp_whatsappChannels",
                 {"whatsappChannels": [{"action": 5, "phoneNumberId": phone_number_id}]})
    if result.get("error"):
        # Don't cache DB errors — the next message retries.
        raise RuntimeError(f"sp_whatsappChannels lookup failed: {result['error']}")
    try:
        rows = result["result"][0]["whatsappChannels"]
    except (KeyError, IndexError, TypeError):
        rows = []
    channel = rows[0] if rows else None
    _channel_cache[phone_number_id] = (time.time() + CHANNEL_CACHE_SECONDS, channel)
    return channel


def access_token(channel: Optional[dict]) -> str:
    """The channel's token setting if it names one, else WA_ACCESS_TOKEN
    (system user of our own Meta portfolio)."""
    ref = (channel or {}).get("accessTokenRef")
    token = os.getenv(ref) if ref else os.getenv("WA_ACCESS_TOKEN")
    if not token:
        raise ValueError(f"Missing access token setting {ref or 'WA_ACCESS_TOKEN'}.")
    return token


def whatsapp_channels_sp(json_file: dict):
    """Admin passthrough for POST /whatsapp/channels. Drops the lookup cache
    after writes so a re-pointed number takes effect right away."""
    try:
        result = _sp("sp_whatsappChannels", json_file)
        action = ((json_file.get("whatsappChannels") or [{}])[0]).get("action")
        if action in (1, 2):
            _channel_cache.clear()
        return JSONResponse(result, status_code=200)
    except Exception as e:
        logger.exception("[whatsappChannels] sp_whatsappChannels failed")
        return JSONResponse({"error": str(e)}, status_code=500)


# ── Conversation state ──────────────────────────────────────────────────────

def _conversation(action: int, channel_id: int, customer_phone: str, **fields) -> dict:
    result = _sp("sp_whatsappConversations", {"whatsappConversations": [{
        **fields, "action": action, "channelId": channel_id, "customerPhone": customer_phone,
    }]})
    if result.get("error"):
        raise RuntimeError(f"sp_whatsappConversations failed: {result['error']}")
    return result["result"][0]


def get_state(channel_id: int, phone: str) -> dict:
    """{"pending": dict|None (already expired → None), "staffPaused": bool,
    "lastBooked": dict|None}"""
    return _conversation(0, channel_id, phone)


def set_pending(channel_id: int, phone: str, fields: dict, ttl_seconds: int) -> None:
    _conversation(1, channel_id, phone, pending=fields, ttlSeconds=ttl_seconds)


def clear_pending(channel_id: int, phone: str) -> None:
    _conversation(2, channel_id, phone)


def pause_for_staff(channel_id: int, phone: str, pause_seconds: int) -> None:
    _conversation(3, channel_id, phone, pauseSeconds=pause_seconds)


def set_last_booked(channel_id: int, phone: str, row: dict) -> None:
    _conversation(4, channel_id, phone, lastBooked=row)


# ── Migration ───────────────────────────────────────────────────────────────

_MIGRATION_FILES = (
    "sql/migrations/2026-09-28_whatsapp_channels.sql",
    "sql/sp_whatsappChannels.sql",
    "sql/sp_whatsappConversations.sql",
)


def run_migration() -> dict:
    """Create the WhatsApp channel tables and SPs (idempotent)."""
    root = os.path.join(os.path.dirname(__file__), "..")
    batches_run = 0
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        for rel_path in _MIGRATION_FILES:
            with open(os.path.abspath(os.path.join(root, rel_path)), encoding="utf-8") as f:
                script = f.read()
            for batch in (b.strip() for b in script.split("\nGO")):
                if batch:
                    cursor.execute(batch)
                    batches_run += 1
        conn.commit()
    finally:
        if conn:
            conn.close()
    return {"ok": True, "batches_run": batches_run}
