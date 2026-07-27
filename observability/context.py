"""
Per-request observability context.

Uses contextvars so the correlationId / workflowId / identity set by
ObservabilityMiddleware are visible to sync route handlers and the modules they
call WITHOUT threading parameters through every function. Starlette copies the
contextvars into the threadpool it uses to run sync endpoints, so this works for
the existing `def route(json: dict)` handlers unchanged.
"""

from __future__ import annotations

import contextvars
import uuid
from typing import Optional

_correlation_id: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar("obs_correlation_id", default=None)
_workflow_id: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar("obs_workflow_id", default=None)
_user_id: contextvars.ContextVar[Optional[int]] = contextvars.ContextVar("obs_user_id", default=None)
_company_id: contextvars.ContextVar[Optional[int]] = contextvars.ContextVar("obs_company_id", default=None)
_client_id: contextvars.ContextVar[Optional[int]] = contextvars.ContextVar("obs_client_id", default=None)
_ip: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar("obs_ip", default=None)
_device: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar("obs_device", default=None)
_app_version: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar("obs_app_version", default=None)
_endpoint: contextvars.ContextVar[Optional[str]] = contextvars.ContextVar("obs_endpoint", default=None)


def _to_int(value) -> Optional[int]:
    try:
        if value in (None, "", "null"):
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def set_request_context(
    *,
    correlation_id: Optional[str] = None,
    workflow_id: Optional[str] = None,
    user_id=None,
    company_id=None,
    client_id=None,
    ip: Optional[str] = None,
    device: Optional[str] = None,
    app_version: Optional[str] = None,
    endpoint: Optional[str] = None,
) -> None:
    _correlation_id.set(correlation_id or str(uuid.uuid4()))
    _workflow_id.set(workflow_id or None)
    _user_id.set(_to_int(user_id))
    _company_id.set(_to_int(company_id))
    _client_id.set(_to_int(client_id))
    _ip.set(ip)
    _device.set(device)
    _app_version.set(app_version)
    _endpoint.set(endpoint)


def bind_workflow(workflow_id: str) -> None:
    """Attach/override the current workflowId (e.g. when a module starts one)."""
    if workflow_id:
        _workflow_id.set(workflow_id)


def new_workflow_id() -> str:
    wid = str(uuid.uuid4())
    _workflow_id.set(wid)
    return wid


def get_context() -> dict:
    return {
        "correlationId": _correlation_id.get(),
        "workflowId": _workflow_id.get(),
        "userId": _user_id.get(),
        "companyId": _company_id.get(),
        "clientId": _client_id.get(),
        "ipAddress": _ip.get(),
        "deviceInfo": _device.get(),
        "appVersion": _app_version.get(),
        "apiEndpoint": _endpoint.get(),
    }
