# Observability

First-class observability for SmartLoans. **Goal: every action by every user can be reconstructed from the logs** — for debugging, auditing, regulatory compliance, fraud investigation, customer support, AI analytics, and performance monitoring.

> Status: code complete and unit-verified. **`sql/sp_observability.sql` must be deployed** to the app DB before any row is written. See [Deployment](#deployment) and [What is / isn't verified](#what-is--isnt-verified).

---

## 1. The lineage model

Two ids tie everything together:

| Id | Scope | Created | Purpose |
|----|-------|---------|---------|
| `workflowId` | One **business process** (registration, loan application, payment) | At process start — frontend on "Create Account"; backend generates one if absent | "One workflow, one trace" — every step of the process shares it |
| `correlationId` | One **HTTP request** | Per request by the middleware (or from an inbound `X-Correlation-Id`) | Links request → response → every downstream integration call |

Plus ambient context on every row: `companyId`, `clientId`, `userId`, `ipAddress`, `deviceInfo`, `appVersion`, `apiEndpoint`.

**Identity is client-asserted** (there is no auth middleware — auth is `/login` + shared secret). The `X-User-Id`/`X-Company-Id`/`X-Client-Id` headers are fine for observability but **must never be used for authorization**.

### How lineage flows end-to-end

```
Frontend                         Backend                          Database
────────                         ───────                          ────────
startWorkflow('client_registration')
  → localStorage workflowId
window.fetch interceptor
  X-Workflow-Id, X-Correlation-Id,
  X-User-Id/Company-Id/Client-Id ──▶ ObservabilityMiddleware
                                       set_request_context(...)  (contextvars)
                                          │
                                          ▼
                                     business code:
                                     log_workflow_step / timed_integration /
                                     log_audit  (read ids from context)
                                          │
                                          ▼
                                     writer → sp_observability_logBatch ──▶ workflowLogs
                                     (audit/SECURITY → sync single-row SP)   auditLogs
                                                                             applicationLogs
                                                                             integrationLogs
```

Because the middleware publishes `workflowId`/`correlationId` into `contextvars` (which Starlette copies into the threadpool that runs the sync route handlers), **every log a request emits is automatically stamped with the same ids — no parameter threading required.**

---

## 2. The four log tables

Created in [`sql/sp_observability.sql`](../sql/sp_observability.sql) (`dbo`, `created_At = SYSUTCDATETIME()` UTC, covering indexes).

| Table | Answers | Write path |
|-------|---------|-----------|
| `workflowLogs` | *What steps did this business process go through?* | async best-effort |
| `auditLogs` | *Who changed what, from what to what?* | **synchronous / durable** |
| `applicationLogs` | *Technical events + one row per request + SECURITY events* | best-effort; **SECURITY = durable** |
| `integrationLogs` | *External calls — Stripe / Azure Face / Blob / Notification Hub / email / SMS / Document Intelligence* | async best-effort |

Key columns: all carry `correlationId`; `workflowLogs`/`applicationLogs`/`integrationLogs` also carry `workflowId`. `workflowLogs` has `stepName`/`status`/`durationMs`/`requestJson`/`responseJson`/`exception`. `auditLogs` has `entityName`/`entityId`/`fieldName`/`oldValue`/`newValue`/`action`. `integrationLogs` has `service`/`operation`/`status`/`latencyMs`.

**Stored procedures:** single-row `sp_workflowLog` / `sp_auditLog` / `sp_applicationLog` / `sp_integrationLog` (durable path) + `sp_observability_logBatch` (async batch path, fans a mixed JSON array into the four tables).

---

## 3. Backend framework — `observability/`

| File | Role |
|------|------|
| `context.py` | `contextvars` trace context; `set_request_context`, `get_context`, `bind_workflow`, `new_workflow_id` |
| `redaction.py` | `redact()` — denylist mask (password, token, card, cvv, otp, curp, descriptor, base64…) + 8 KB cap; **never stores base64 images** |
| `writer.py` | Background daemon thread + `queue`; batches best-effort logs through one persistent connection (avoids per-call connect churn); `write_now()` for durable audit/SECURITY. **All failures swallowed + counted — never raised into a request** |
| `logger.py` | `log_workflow_step`, `workflow_step()` (timing context manager), `log_audit`, `log_application`, `log_integration` |
| `integrations.py` | `timed_integration(service, operation)` — wraps an external call, emits an `integrationLogs` row with latency/status/redacted summaries |
| `middleware.py` | `ObservabilityMiddleware` — reads headers, sets context, times the request, emits one `applicationLog`, echoes `X-Correlation-Id` |

Wired in [`main.py`](../main.py): `app.add_middleware(ObservabilityMiddleware)` + `writer.start()` on startup / `writer.flush_and_stop()` on shutdown.

### Usage in business code

```python
from observability import timed_integration, workflow_step, log_audit, log_workflow_step

# External-service call → integrationLogs (latency, status, redacted)
with timed_integration("stripe", "create_customer") as span:
    resp = stripe.Customer.create(**payload)
    span.http_status = 200

# A business milestone → workflowLogs (timed, SUCCESS/FAILED auto)
with workflow_step("OCR Executed", workflow_name="client_registration"):
    result = await analyze(...)

# A data change → auditLogs (durable, old → new)
log_audit("users", user_id, "cellphone", old_phone, new_phone, action="UPDATE")
```

---

## 4. Frontend propagation

- [`src/utils/observability.ts`](../../POSVending/src/utils/observability.ts) — a **global `window.fetch` interceptor** installed once in `main.tsx`. On backend-host calls only, it injects `X-Correlation-Id`, `X-Workflow-Id`, `X-User-Id/Company-Id/Client-Id`, `X-App-Version`, `X-Device`. Third-party URLs are left untouched. This avoids editing the 25+ api modules.
- `src/contexts/ObservabilityContext.tsx` — `startWorkflow(name)` / `endWorkflow()` lifecycle.
- `CreateAccount.tsx` — starts `client_registration` on account creation, ends it at completion.

---

## 5. What is instrumented today

The framework auto-traces **every request** (one `applicationLog`). Business-level instrumentation so far:

- `modules/users.py` — **User Created**, **OTP Verified**, **Verification Sent** (+ email/SMS `integrationLogs`); **audit** on `cellphone`/`email`/`name` changes (before-image snapshot).
- `modules/login.py` — **SECURITY** event on failed login (never logs the password).
- `modules/document_intelligence.py` — **OCR Executed** (+ Document Intelligence `integrationLogs`).

The remaining registration milestones (blob upload, face compare, liveness, credit score, contract, signature, wallet, Stripe customer, push) each follow the same one-line `workflow_step` / `timed_integration` pattern.

---

## 6. Reading the observability

All data lives in the four **tables** (there is no CSV/file log output). Query cookbook: [`sql/observability_queries.sql`](../sql/observability_queries.sql) — 12 ready-to-run queries:

- Full workflow trace by `workflowId` (the lineage view)
- Everything in one request by `correlationId` (union across all four tables)
- Failed steps, recent errors
- Performance metrics per endpoint (calls / avg / **p95** / error %)
- Integration latency + error rate per service
- Audit trail, security (failed-login grouping)
- Registration funnel, stuck workflows, per-client activity

---

## 7. Deployment

1. Deploy [`sql/sp_observability.sql`](../sql/sp_observability.sql) to the app DB (`montanogilberto_smartloans` on `sql.bsite.net\MSSQL2016`) — creates the four tables + SPs. Idempotent (`IF NOT EXISTS` guards), safe to re-run.
2. Deploy the backend (the middleware + writer are already wired in `main.py`).
3. Deploy the frontend (fetch interceptor installs at bootstrap).

Until step 1 is done, all logging **safely no-ops** (the writer counts `dropped` and never raises).

---

## 8. What is / isn't verified

**Confirmed:**
- Redaction masks password / OTP / cardNumber / base64 → `***`, preserves normal fields.
- Logging helpers never raise without a DB; durable path counts `dropped` on failure.
- **Lineage propagation (in-process):** across 2 requests × 3 log types, all rows carried the **same `workflowId`** while each request kept its own `correlationId` — proving the workflow trace reconstructs.
- Frontend interceptor injects all trace headers on backend calls; third-party URLs untouched (verified live).
- Backend compiles + imports with `ObservabilityMiddleware` outermost; frontend `tsc` clean.

**Not yet verified (blocked on deployment — no live DB here):**
- The DB round-trip: a row actually landing in a table via `sp_observability_logBatch`.
- The middleware binding headers → context at real HTTP request time (standard Starlette contextvar behavior, but not exercised end-to-end).
- A full multi-request registration producing one `workflowId` trace **in the tables**.

After deploying, confirm with query #1 (trace) and #2 (by correlationId) in the cookbook.

---

## 8b. Debug logging (opt-in)

Both sides are silent by default. To watch the pipeline live (useful before the DB is deployed):
- **Backend:** run the API with `OBS_DEBUG=1` → prints `[obs] → <endpoint> cid= … wid= …`, `[obs] enqueue <type> …`, `[obs] batch flushed N rows`, and swallowed-failure lines.
- **Frontend:** `localStorage.setItem('obs_debug','1')` (or a Vite dev build) → `[obs] workflow START/END` and `[obs] → <url> {correlationId, workflowId, userId}`.

Off by default → no production noise, no perf cost.

## 9. Follow-ups (not in this pass)

- Instrument the remaining registration milestones + other workflows (loan application, payment, collections).
- Retention: partitioning / archival job (these tables grow ~18k+ rows/day).
- Per-account login attempt counter / lockout.
- Dashboards + alerting; export to OpenTelemetry / Azure Application Insights / Grafana. The four-table split is designed so these can be added without redesign.

---

## 10. Governance note

This layer is **hand-written cross-cutting infrastructure** — an intentional exception to the posgmo-factory PRD pipeline (the factory model doesn't cover middleware). The factory has been made aware of it: `ArchitecturePOSGMO/CLAUDE.md` (Observability section + Core Rule 6), the four tables registered in `Database/structure_database.csv`, and instrumentation rules added to the backend/database agent prompts — so future generated modules instrument themselves and don't recreate the log tables.
