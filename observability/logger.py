"""
Business-facing logging API.

Every helper reads the ambient request context (correlationId / workflowId /
identity) from observability.context, so callers only pass what's specific to the
event. Best-effort logs are enqueued; audit + SECURITY logs are written durably.

All helpers swallow their own errors — logging must never break business logic.
"""

from __future__ import annotations

import time
import traceback
from contextlib import contextmanager
from typing import Any, Optional

from .context import get_context
from .redaction import redact
from .writer import writer


def _base() -> dict:
    ctx = get_context()
    return {
        "correlationId": ctx.get("correlationId"),
        "workflowId": ctx.get("workflowId"),
        "companyId": ctx.get("companyId"),
    }


def log_workflow_step(
    step_name: str,
    *,
    action: Optional[str] = None,
    status: str = "SUCCESS",
    workflow_name: Optional[str] = None,
    entity: Optional[str] = None,
    entity_id: Optional[int] = None,
    message: Optional[str] = None,
    duration_ms: Optional[int] = None,
    request: Any = None,
    response: Any = None,
    exception: Optional[str] = None,
) -> None:
    try:
        ctx = get_context()
        writer.enqueue({
            "logType": "workflow",
            "workflowId": ctx.get("workflowId"),
            "correlationId": ctx.get("correlationId"),
            "companyId": ctx.get("companyId"),
            "clientId": ctx.get("clientId"),
            "userId": ctx.get("userId"),
            "entityName": entity,
            "entityId": entity_id,
            "workflowName": workflow_name,
            "stepName": step_name,
            "actionName": action,
            "status": status,
            "message": message,
            "durationMs": duration_ms,
            "requestJson": redact(request) if request is not None else None,
            "responseJson": redact(response) if response is not None else None,
            "exception": exception,
            "ipAddress": ctx.get("ipAddress"),
            "deviceInfo": ctx.get("deviceInfo"),
            "appVersion": ctx.get("appVersion"),
            "apiEndpoint": ctx.get("apiEndpoint"),
        })
    except Exception:
        pass


@contextmanager
def workflow_step(step_name: str, *, workflow_name: Optional[str] = None,
                  entity: Optional[str] = None, entity_id: Optional[int] = None,
                  action: Optional[str] = None):
    """Time a block and emit a SUCCESS/FAILED workflow step. Re-raises on error."""
    start = time.monotonic()
    try:
        yield
    except Exception as exc:
        log_workflow_step(
            step_name, action=action, status="FAILED", workflow_name=workflow_name,
            entity=entity, entity_id=entity_id,
            duration_ms=int((time.monotonic() - start) * 1000),
            message=str(exc), exception=traceback.format_exc(),
        )
        raise
    else:
        log_workflow_step(
            step_name, action=action, status="SUCCESS", workflow_name=workflow_name,
            entity=entity, entity_id=entity_id,
            duration_ms=int((time.monotonic() - start) * 1000),
        )


def log_audit(
    entity: str,
    entity_id: Optional[int],
    field: Optional[str],
    old_value: Any,
    new_value: Any,
    *,
    action: str = "UPDATE",
) -> None:
    """Durable: who changed what. Compliance trail."""
    try:
        ctx = get_context()
        writer.write_now("audit", {
            "logType": "audit",
            "correlationId": ctx.get("correlationId"),
            "companyId": ctx.get("companyId"),
            "actorUserId": ctx.get("userId"),
            "actorClientId": ctx.get("clientId"),
            "entityName": entity,
            "entityId": entity_id,
            "fieldName": field,
            "oldValue": None if old_value is None else str(old_value),
            "newValue": None if new_value is None else str(new_value),
            "action": action,
            "ipAddress": ctx.get("ipAddress"),
            "deviceInfo": ctx.get("deviceInfo"),
        })
    except Exception:
        pass


def log_application(
    level: str,
    source: str,
    message: str,
    *,
    exception: Optional[str] = None,
    http_status: Optional[int] = None,
    duration_ms: Optional[int] = None,
) -> None:
    """INFO/WARN/ERROR enqueued best-effort; SECURITY written durably."""
    try:
        ctx = get_context()
        row = {
            "logType": "application",
            "correlationId": ctx.get("correlationId"),
            "workflowId": ctx.get("workflowId"),
            "companyId": ctx.get("companyId"),
            "level": level,
            "source": source,
            "message": message,
            "exception": exception,
            "apiEndpoint": ctx.get("apiEndpoint"),
            "httpStatus": http_status,
            "durationMs": duration_ms,
            "ipAddress": ctx.get("ipAddress"),
        }
        if level == "SECURITY":
            writer.write_now("application", row)
        else:
            writer.enqueue(row)
    except Exception:
        pass


def log_integration(
    service: str,
    operation: str,
    *,
    status: str = "SUCCESS",
    http_status: Optional[int] = None,
    latency_ms: Optional[int] = None,
    request: Any = None,
    response: Any = None,
    exception: Optional[str] = None,
) -> None:
    try:
        ctx = get_context()
        writer.enqueue({
            "logType": "integration",
            "correlationId": ctx.get("correlationId"),
            "workflowId": ctx.get("workflowId"),
            "companyId": ctx.get("companyId"),
            "service": service,
            "operation": operation,
            "status": status,
            "httpStatus": http_status,
            "latencyMs": latency_ms,
            "requestSummary": redact(request) if request is not None else None,
            "responseSummary": redact(response) if response is not None else None,
            "exception": exception,
        })
    except Exception:
        pass
