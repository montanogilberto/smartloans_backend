-- ============================================================
-- Observability query cookbook
-- ============================================================
-- Read/analysis queries for the four log tables created in
-- sp_observability.sql:  workflowLogs · auditLogs · applicationLogs · integrationLogs
--
-- Each query is self-contained — copy the one you need. Replace the
-- <PLACEHOLDER> literals (workflowId / correlationId / companyId / clientId).
-- Times are UTC (created_At = SYSUTCDATETIME()).
-- ============================================================


-- ── 1. Full workflow trace — "one workflow, one trace" ──────
-- Every step of a single business process, in order. This is the
-- registration/loan/payment reconstruction view.
SELECT stepName, actionName, status, durationMs, message, exception,
       apiEndpoint, created_At
FROM   dbo.workflowLogs
WHERE  workflowId = '<WORKFLOW_ID>'
ORDER  BY workflowLogId;   -- insertion order = execution order


-- ── 2. Everything that happened in ONE http request ─────────
-- Correlate a single request across all four tables (workflow steps,
-- integration calls, app log, any audit rows). Great for support tickets:
-- the response carries X-Correlation-Id, paste it here.
SELECT 'workflow'    AS logType, created_At, stepName AS detail, status, durationMs, exception
FROM   dbo.workflowLogs    WHERE correlationId = '<CORRELATION_ID>'
UNION ALL
SELECT 'integration', created_At, service + ':' + operation, status, latencyMs, exception
FROM   dbo.integrationLogs WHERE correlationId = '<CORRELATION_ID>'
UNION ALL
SELECT 'application', created_At, [level] + ' ' + ISNULL(source,''), CAST(httpStatus AS VARCHAR), durationMs, exception
FROM   dbo.applicationLogs  WHERE correlationId = '<CORRELATION_ID>'
UNION ALL
SELECT 'audit',       created_At, entityName + '.' + ISNULL(fieldName,''), action, NULL, NULL
FROM   dbo.auditLogs        WHERE correlationId = '<CORRELATION_ID>'
ORDER  BY created_At;


-- ── 3. Where did it fail? — recent FAILED workflow steps ────
SELECT TOP 100 workflowId, workflowName, stepName, message, exception,
       durationMs, apiEndpoint, companyId, clientId, created_At
FROM   dbo.workflowLogs
WHERE  status = 'FAILED'
  AND  created_At >= DATEADD(DAY, -7, SYSUTCDATETIME())
ORDER  BY created_At DESC;


-- ── 4. Performance metrics per endpoint (calls / avg / p95 / error %) ──
-- Mirrors the "Performance Metrics" panel: /api/login → avg 180ms, p95 600ms, etc.
WITH agg AS (
    SELECT apiEndpoint,
           COUNT(*)      AS calls,
           AVG(durationMs) AS avgMs,
           MAX(durationMs) AS maxMs,
           CAST(100.0 * SUM(CASE WHEN httpStatus >= 500 OR [level] = 'ERROR' THEN 1 ELSE 0 END)
                / COUNT(*) AS DECIMAL(5,2)) AS errorPct
    FROM   dbo.applicationLogs
    WHERE  created_At >= DATEADD(DAY, -1, SYSUTCDATETIME())
      AND  apiEndpoint IS NOT NULL
    GROUP  BY apiEndpoint
),
p95 AS (
    SELECT DISTINCT apiEndpoint,
           PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY durationMs)
               OVER (PARTITION BY apiEndpoint) AS p95Ms
    FROM   dbo.applicationLogs
    WHERE  created_At >= DATEADD(DAY, -1, SYSUTCDATETIME())
      AND  durationMs IS NOT NULL
)
SELECT a.apiEndpoint, a.calls, a.avgMs, p.p95Ms, a.maxMs, a.errorPct
FROM   agg a
LEFT   JOIN p95 p ON p.apiEndpoint = a.apiEndpoint
ORDER  BY a.calls DESC;


-- ── 5. External integrations — latency + error rate per service ──
-- Stripe / Azure Face / Blob / Notification Hub / email / SMS health.
SELECT service,
       COUNT(*)        AS calls,
       AVG(latencyMs)  AS avgLatencyMs,
       MAX(latencyMs)  AS maxLatencyMs,
       CAST(100.0 * SUM(CASE WHEN status = 'FAILED' THEN 1 ELSE 0 END)
            / COUNT(*) AS DECIMAL(5,2)) AS errorPct
FROM   dbo.integrationLogs
WHERE  created_At >= DATEADD(DAY, -1, SYSUTCDATETIME())
GROUP  BY service
ORDER  BY calls DESC;


-- ── 6. Slowest recent integration calls (drill-down) ───────
SELECT TOP 50 service, operation, status, httpStatus, latencyMs,
       exception, correlationId, created_At
FROM   dbo.integrationLogs
WHERE  created_At >= DATEADD(DAY, -1, SYSUTCDATETIME())
ORDER  BY latencyMs DESC;


-- ── 7. Audit trail — who changed what ──────────────────────
-- All changes to one record (e.g. a user's profile).
SELECT actorUserId, actorClientId, fieldName, oldValue, newValue, action,
       ipAddress, deviceInfo, correlationId, created_At
FROM   dbo.auditLogs
WHERE  entityName = 'users'          -- e.g. 'users' | 'clients'
  AND  entityId   = '<ENTITY_ID>'
ORDER  BY created_At DESC;


-- ── 8. Security — failed login attempts, grouped by user + IP ──
-- Surfaces brute-force patterns (attempts per username/IP).
SELECT message, ipAddress, COUNT(*) AS attempts,
       MIN(created_At) AS firstAttempt, MAX(created_At) AS lastAttempt
FROM   dbo.applicationLogs
WHERE  [level] = 'SECURITY'
  AND  created_At >= DATEADD(DAY, -1, SYSUTCDATETIME())
GROUP  BY message, ipAddress
HAVING COUNT(*) >= 1
ORDER  BY attempts DESC, lastAttempt DESC;


-- ── 9. Recent technical errors (ERROR level) ───────────────
SELECT TOP 100 source, message, exception, apiEndpoint, httpStatus,
       durationMs, correlationId, companyId, created_At
FROM   dbo.applicationLogs
WHERE  [level] = 'ERROR'
  AND  created_At >= DATEADD(DAY, -1, SYSUTCDATETIME())
ORDER  BY created_At DESC;


-- ── 10. Registration funnel — step completion counts ───────
-- How many registrations reached each step in the last 30 days,
-- and how long each step takes on average.
SELECT stepName,
       SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) AS succeeded,
       SUM(CASE WHEN status = 'FAILED'  THEN 1 ELSE 0 END) AS failed,
       AVG(durationMs) AS avgMs
FROM   dbo.workflowLogs
WHERE  workflowName = 'client_registration'
  AND  created_At >= DATEADD(DAY, -30, SYSUTCDATETIME())
GROUP  BY stepName
ORDER  BY MIN(workflowLogId);   -- keeps step order


-- ── 11. All activity for one client (support / fraud) ──────
SELECT 'workflow' AS logType, workflowName AS ctx, stepName AS detail, status, created_At
FROM   dbo.workflowLogs WHERE clientId = '<CLIENT_ID>'
UNION ALL
SELECT 'audit', entityName, ISNULL(fieldName,'') + ': ' + ISNULL(oldValue,'') + ' -> ' + ISNULL(newValue,''), action, created_At
FROM   dbo.auditLogs   WHERE actorClientId = '<CLIENT_ID>'
ORDER  BY created_At DESC;


-- ── 12. Stuck / incomplete workflows ───────────────────────
-- Started but never reached a terminal 'Completed'/'Registration Completed'
-- step in the last 2 days — candidates for follow-up.
SELECT w.workflowId, MAX(w.workflowName) AS workflowName,
       MAX(w.clientId) AS clientId, MAX(w.companyId) AS companyId,
       COUNT(*) AS steps, MAX(w.created_At) AS lastStepAt
FROM   dbo.workflowLogs w
WHERE  w.created_At >= DATEADD(DAY, -2, SYSUTCDATETIME())
GROUP  BY w.workflowId
HAVING SUM(CASE WHEN w.stepName LIKE '%Completed%' THEN 1 ELSE 0 END) = 0
ORDER  BY lastStepAt DESC;

-- ═══════════════════════════════════════════════════════════════════════════
-- ¿DÓNDE ESTÁ EL DINERO? — rastro de dinero via observabilidad (2026-08)
-- Todos los movimientos escriben workflowName='money_trail' en workflowLogs y
-- las llamadas a Stripe/STP quedan en integrationLogs (service stripe|stp).
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) Rastro cronológico de dinero (últimas 48 h): intent → cargo → cartera → SPEI/transfer
SELECT created_At, stepName, actionName, status, entityName, entityId, message,
       clientId, correlationId, workflowId
FROM dbo.workflowLogs
WHERE workflowName = 'money_trail'
  AND created_At >= DATEADD(HOUR, -48, SYSUTCDATETIME())
ORDER BY created_At DESC;

-- 2) Rastro de UNA operación completa (por correlationId de cualquier paso)
-- SELECT * FROM dbo.workflowLogs WHERE correlationId = '...' ORDER BY created_At;

-- 3) Llamadas reales a los rieles (Stripe / STP): latencia, éxito, respuesta
SELECT created_At, serviceName, operationName, status, latencyMs, responseJson
FROM dbo.integrationLogs
WHERE serviceName IN ('stripe', 'stp')
ORDER BY created_At DESC;

-- 4) Movimientos de dinero FALLIDOS (cargo rechazado, SPEI reversado)
SELECT created_At, stepName, actionName, message, clientId, correlationId
FROM dbo.workflowLogs
WHERE workflowName = 'money_trail' AND status = 'FAILED'
ORDER BY created_At DESC;

-- 5) Conciliación rápida: por cliente, últimos movimientos de cartera con saldo resultante
SELECT TOP 50 created_At, entityId AS clientId, stepName, actionName, message
FROM dbo.workflowLogs
WHERE workflowName = 'money_trail' AND entityName = 'clientWallets'
ORDER BY created_At DESC;
