"""
SmartLoans observability layer.

First-class logging so every user action can be reconstructed:
  * workflowLogs     — business process steps under one workflowId
  * auditLogs        — who changed what (durable)
  * applicationLogs  — technical + security events
  * integrationLogs  — external service calls (Stripe, Azure, ...)

Public API:
  from observability import (
      ObservabilityMiddleware, writer,
      log_workflow_step, workflow_step, log_audit, log_application,
      log_integration, timed_integration,
      bind_workflow, new_workflow_id, get_context,
  )
"""

from .context import bind_workflow, get_context, new_workflow_id, set_request_context
from .integrations import timed_integration
from .logger import (
    log_application,
    log_audit,
    log_integration,
    log_workflow_step,
    workflow_step,
)
from .middleware import ObservabilityMiddleware
from .writer import writer

__all__ = [
    "ObservabilityMiddleware",
    "writer",
    "set_request_context",
    "bind_workflow",
    "new_workflow_id",
    "get_context",
    "log_workflow_step",
    "workflow_step",
    "log_audit",
    "log_application",
    "log_integration",
    "timed_integration",
]
