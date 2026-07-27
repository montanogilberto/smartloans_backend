"""
Wrapper for external-service calls (Stripe, Azure Face, Azure Blob, Notification
Hub, email/SMS, Document Intelligence).

Usage:

    from observability.integrations import timed_integration

    with timed_integration("stripe", "create_customer", request=payload) as span:
        resp = stripe.Customer.create(**payload)
        span.response = resp
        span.http_status = 200

On exit it emits one integrationLogs row with latency, status, and redacted
summaries. Exceptions are logged as FAILED and re-raised.
"""

from __future__ import annotations

import time
import traceback
from contextlib import contextmanager
from typing import Any, Optional

from .logger import log_integration


class _Span:
    __slots__ = ("response", "http_status")

    def __init__(self) -> None:
        self.response: Any = None
        self.http_status: Optional[int] = None


@contextmanager
def timed_integration(service: str, operation: str, *, request: Any = None):
    span = _Span()
    start = time.monotonic()
    status = "SUCCESS"
    exc_text = None
    try:
        yield span
    except Exception:
        status = "FAILED"
        exc_text = traceback.format_exc()
        raise
    finally:
        log_integration(
            service, operation,
            status=status,
            http_status=span.http_status,
            latency_ms=int((time.monotonic() - start) * 1000),
            request=request,
            response=span.response,
            exception=exc_text,
        )
