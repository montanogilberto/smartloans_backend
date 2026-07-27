"""
Redaction + size-capping for anything stored in a log body.

Compliance-critical: request/response payloads on a financial platform contain
passwords, card tokens, OTPs, CURP and base64 INE/face images. None of that may
land in the log tables. `redact()` walks the structure, masks denylisted keys,
drops values that look like base64 image blobs, and truncates the serialized
result to a hard cap.
"""

from __future__ import annotations

import json
import re
from typing import Any

# Key names whose values are masked wholesale (case-insensitive substring match).
_DENY_KEYS = (
    "password", "passwd", "pwd",
    "token", "secret", "apikey", "api_key", "authorization", "auth",
    "card", "cardnumber", "cvv", "cvc", "pan",
    "otp", "pin",
    "curp", "rfc", "ssn",
    "descriptor", "embedding",
    "imagebase64", "idfrontimagebase64", "idbackimagebase64",
    "selfiebase64", "selfie", "base64", "imagedata",
)

_MASK = "***"
_MAX_SERIALIZED_CHARS = 8_000
# A long, mostly-base64-looking string is almost certainly image/binary data.
_BASE64_RE = re.compile(r"^[A-Za-z0-9+/=\s]{256,}$")
_DATA_URI_RE = re.compile(r"^data:[^;]+;base64,", re.IGNORECASE)


def _key_is_sensitive(key: str) -> bool:
    k = key.lower().replace("_", "")
    return any(deny.replace("_", "") in k for deny in _DENY_KEYS)


def _looks_like_blob(value: str) -> bool:
    if _DATA_URI_RE.match(value):
        return True
    return bool(_BASE64_RE.match(value)) and len(value) >= 256


def _redact_value(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: (_MASK if _key_is_sensitive(k) else _redact_value(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [_redact_value(v) for v in value]
    if isinstance(value, str) and _looks_like_blob(value):
        return f"<{len(value)} bytes redacted>"
    return value


def redact(obj: Any) -> str:
    """Return a redacted, size-capped JSON string safe to store in a log column."""
    if obj is None:
        return None  # type: ignore[return-value]
    try:
        cleaned = _redact_value(obj)
        text = cleaned if isinstance(cleaned, str) else json.dumps(cleaned, default=str, ensure_ascii=False)
    except Exception:
        # Never let redaction failure break logging — store a marker instead.
        return "<unserializable>"
    if len(text) > _MAX_SERIALIZED_CHARS:
        text = text[:_MAX_SERIALIZED_CHARS] + f"...<truncated {len(text) - _MAX_SERIALIZED_CHARS} chars>"
    return text
