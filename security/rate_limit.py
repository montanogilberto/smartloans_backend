# security/rate_limit.py
"""Sliding-window limits for the public routes that send messages.

Counters live in this process: they reset on restart and each App Service
instance counts on its own, so a scaled-out app allows limit x instances. Good
enough to stop message bombing and SMS bills; move to a shared store if the app
ever scales out.
"""
import re
import threading
import time
from collections import deque
from typing import Callable, Optional

from fastapi import Request
from fastapi.responses import JSONResponse

MESSAGE = "Demasiados intentos. Intenta de nuevo más tarde."

_MAX_KEYS = 50_000
_MAX_WINDOW_SECONDS = 3600

_hits: dict[str, deque] = {}
_lock = threading.Lock()


class RateLimitExceeded(Exception):
    def __init__(self, retry_after: int):
        self.retry_after = retry_after


async def rate_limit_handler(_request: Request, exc: RateLimitExceeded) -> JSONResponse:
    # "error", not FastAPI's "detail": it is the key the POS shows to the user.
    return JSONResponse({"error": MESSAGE}, status_code=429,
                        headers={"Retry-After": str(exc.retry_after)})


def reset() -> None:
    with _lock:
        _hits.clear()


def _prune(now: float) -> None:
    for key in [k for k, q in _hits.items() if not q or now - q[-1] > _MAX_WINDOW_SECONDS]:
        del _hits[key]
    if len(_hits) >= _MAX_KEYS:
        _hits.clear()


def _hit(key: str, limit: int, window: int) -> None:
    now = time.monotonic()
    with _lock:
        if len(_hits) >= _MAX_KEYS:
            _prune(now)
        queue = _hits.setdefault(key, deque())
        while queue and now - queue[0] >= window:
            queue.popleft()
        if len(queue) >= limit:
            raise RateLimitExceeded(max(1, int(window - (now - queue[0]))))
        queue.append(now)


def client_ip(request: Request) -> str:
    """Azure's front end appends the real client to X-Forwarded-For as ip:port,
    so only the last entry is trustworthy: anything before it is caller-supplied."""
    last = request.headers.get("x-forwarded-for", "").split(",")[-1].strip()
    if last.startswith("["):
        return last[1:].split("]")[0]
    if last:
        return last.split(":")[0] if last.count(":") == 1 else last
    return request.client.host if request.client else "unknown"


def _normalize_target(value: object) -> str:
    text = str(value).strip().lower()
    if "@" in text:
        return text
    return re.sub(r"\D", "", text)[-10:] or text


def field(name: str) -> Callable[[dict], object]:
    """The target is a top-level body key: { "target": ... }."""
    return lambda body: body.get(name)


def row_field(collection: str, name: str) -> Callable[[dict], object]:
    """The target is inside the first row: { "<collection>": [{ "<name>": ... }] }."""
    def read(body: dict) -> object:
        rows = body.get(collection)
        first = rows[0] if isinstance(rows, list) and rows else None
        return first.get(name) if isinstance(first, dict) else None
    return read


def rate_limit(bucket: str, *, per_ip: int, per_target: int, window: int,
               target: Optional[Callable[[dict], object]] = None):
    """Route dependency. Routes that pass the same bucket share their counters,
    so a phone can't be hit once per route."""
    async def dependency(request: Request) -> None:
        _hit(f"{bucket}:ip:{client_ip(request)}", per_ip, window)
        if target is None:
            return
        try:
            body = await request.json()
        except Exception:
            return  # the route rejects the bad body itself
        value = target(body) if isinstance(body, dict) else None
        if value:
            _hit(f"{bucket}:target:{_normalize_target(value)}", per_target, window)
    return dependency
