"""
ObservabilityMiddleware — the request entry point of the observability layer.

Reads the trace/identity headers the frontend sends (or generates a
correlationId), publishes them into the request context, times the request, and
emits an applicationLog for requests worth investigating (errors, 4xx, slow). Echoes X-Correlation-Id back so a caller
(or support agent) can quote the exact trace.

Identity headers are client-asserted (there is no auth middleware) — fine for
observability, never for authorization.
"""

from __future__ import annotations

import time
import traceback
import uuid
from typing import Optional

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from .context import set_request_context
from .debug import dbg
from .logger import log_application

# Paths that would only add noise (Azure health probes hit /health constantly).
_SKIP_PATHS = {"/health", "/docs", "/openapi.json", "/redoc", "/favicon.ico"}

# A request at or above this duration is logged even when it succeeded.
SLOW_REQUEST_MS = 2000


def _request_log_level(status_code: int, duration_ms: int, error: Optional[str]) -> Optional[str]:
    """Level for the per-request applicationLog, or None to skip it.

    Logging every successful call filled the 50 MB database (applicationLogs was
    ~45% of it), so only requests worth investigating are written.
    """
    if error or status_code >= 500:
        return "ERROR"
    if status_code >= 400 or duration_ms >= SLOW_REQUEST_MS:
        return "WARN"
    return None


class ObservabilityMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        if path in _SKIP_PATHS or request.method == "OPTIONS":
            return await call_next(request)

        h = request.headers
        correlation_id = h.get("x-correlation-id") or str(uuid.uuid4())
        client_ip = request.client.host if request.client else h.get("x-forwarded-for")
        endpoint = f"{request.method} {path}"

        set_request_context(
            correlation_id=correlation_id,
            workflow_id=h.get("x-workflow-id"),
            user_id=h.get("x-user-id"),
            company_id=h.get("x-company-id"),
            client_id=h.get("x-client-id"),
            ip=client_ip,
            device=h.get("x-device"),
            app_version=h.get("x-app-version"),
            endpoint=endpoint,
        )

        dbg("→", endpoint, "cid=", correlation_id, "wid=", h.get("x-workflow-id"))
        start = time.monotonic()
        status_code = 500
        error = None
        try:
            response = await call_next(request)
            status_code = response.status_code
            response.headers["X-Correlation-Id"] = correlation_id
            return response
        except Exception:
            error = traceback.format_exc()
            raise
        finally:
            duration_ms = int((time.monotonic() - start) * 1000)
            level = _request_log_level(status_code, duration_ms, error)
            dbg("←", endpoint, "status=", status_code, f"{duration_ms}ms")
            if level:
                log_application(
                    level, "http", endpoint,
                    exception=error, http_status=status_code, duration_ms=duration_ms,
                )
