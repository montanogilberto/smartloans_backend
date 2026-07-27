-- ============================================================
-- Observability layer  —  workflow / audit / application / integration logs
-- ============================================================
-- First-class observability for SmartLoans (financial platform). Goal: every
-- action by every user can be reconstructed from these logs for debugging,
-- audit, regulatory compliance, fraud investigation, support and analytics.
--
-- Correlation model:
--   workflowId   UNIQUEIDENTIFIER — one per business process (registration,
--                loan application, payment). Every step reuses it.
--   correlationId UNIQUEIDENTIFIER — one per HTTP request; links request →
--                response → every downstream integration call.
--
-- Write path (see observability/writer.py):
--   auditLogs + SECURITY applicationLogs  → written synchronously (durable).
--   workflow / application / integration  → async best-effort batch writer
--                                           via sp_observability_logBatch.
--
-- IMPORTANT: request/response bodies are REDACTED + size-capped by the backend
-- before they ever reach these columns (no passwords, tokens, OTPs, CURP or
-- base64 image data). Do not remove that redaction.
--
-- Volume note: high-traffic (~18k logins/day). Indexes ship now; a
-- partitioning / archival job (rows older than N months → cold storage) is a
-- documented follow-up, not part of this deployment.
-- ============================================================

-- ── Table: workflowLogs ─────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'workflowLogs')
CREATE TABLE [dbo].[workflowLogs] (
    workflowLogId   BIGINT IDENTITY PRIMARY KEY,
    workflowId      UNIQUEIDENTIFIER NOT NULL,
    correlationId   UNIQUEIDENTIFIER NULL,
    companyId       INT              NOT NULL,
    clientId        INT              NULL,
    userId          INT              NULL,
    entityName      VARCHAR(100)     NULL,
    entityId        INT              NULL,
    workflowName    VARCHAR(100)     NULL,
    stepName        VARCHAR(100)     NULL,
    actionName      VARCHAR(100)     NULL,
    status          VARCHAR(30)      NULL,   -- STARTED | SUCCESS | FAILED
    message         NVARCHAR(MAX)    NULL,
    durationMs      INT              NULL,
    requestJson     NVARCHAR(MAX)    NULL,   -- redacted + capped upstream
    responseJson    NVARCHAR(MAX)    NULL,   -- redacted + capped upstream
    exception       NVARCHAR(MAX)    NULL,
    ipAddress       VARCHAR(50)      NULL,
    deviceInfo      VARCHAR(200)     NULL,
    appVersion      VARCHAR(50)      NULL,
    apiEndpoint     VARCHAR(200)     NULL,
    created_At      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_workflowLogs_workflowId')
    CREATE INDEX IX_workflowLogs_workflowId    ON [dbo].[workflowLogs] (workflowId, created_At);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_workflowLogs_correlationId')
    CREATE INDEX IX_workflowLogs_correlationId ON [dbo].[workflowLogs] (correlationId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_workflowLogs_company_name')
    CREATE INDEX IX_workflowLogs_company_name  ON [dbo].[workflowLogs] (companyId, workflowName, created_At);
GO

-- ── Table: auditLogs (who changed what — durable) ───────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'auditLogs')
CREATE TABLE [dbo].[auditLogs] (
    auditLogId      BIGINT IDENTITY PRIMARY KEY,
    correlationId   UNIQUEIDENTIFIER NULL,
    companyId       INT              NOT NULL,
    actorUserId     INT              NULL,
    actorClientId   INT              NULL,
    entityName      VARCHAR(100)     NOT NULL,   -- e.g. 'users', 'clients'
    entityId        INT              NULL,
    fieldName       VARCHAR(100)     NULL,       -- e.g. 'cellphone'
    oldValue        NVARCHAR(MAX)    NULL,
    newValue        NVARCHAR(MAX)    NULL,
    action          VARCHAR(30)      NULL,       -- CREATE | UPDATE | DELETE
    ipAddress       VARCHAR(50)      NULL,
    deviceInfo      VARCHAR(200)     NULL,
    created_At      DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_auditLogs_correlationId')
    CREATE INDEX IX_auditLogs_correlationId ON [dbo].[auditLogs] (correlationId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_auditLogs_entity')
    CREATE INDEX IX_auditLogs_entity        ON [dbo].[auditLogs] (companyId, entityName, entityId, created_At);
GO

-- ── Table: applicationLogs (technical + security) ───────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'applicationLogs')
CREATE TABLE [dbo].[applicationLogs] (
    applicationLogId BIGINT IDENTITY PRIMARY KEY,
    correlationId    UNIQUEIDENTIFIER NULL,
    workflowId       UNIQUEIDENTIFIER NULL,
    companyId        INT              NULL,
    [level]          VARCHAR(20)      NOT NULL,  -- INFO | WARN | ERROR | SECURITY
    source           VARCHAR(150)     NULL,      -- module / endpoint
    message          NVARCHAR(MAX)    NULL,
    exception        NVARCHAR(MAX)    NULL,
    apiEndpoint      VARCHAR(200)     NULL,
    httpStatus       INT              NULL,
    durationMs       INT              NULL,
    ipAddress        VARCHAR(50)      NULL,
    created_At       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_applicationLogs_correlationId')
    CREATE INDEX IX_applicationLogs_correlationId ON [dbo].[applicationLogs] (correlationId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_applicationLogs_level_time')
    CREATE INDEX IX_applicationLogs_level_time    ON [dbo].[applicationLogs] ([level], created_At);
GO

-- ── Table: integrationLogs (external service calls) ─────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'integrationLogs')
CREATE TABLE [dbo].[integrationLogs] (
    integrationLogId BIGINT IDENTITY PRIMARY KEY,
    correlationId    UNIQUEIDENTIFIER NULL,
    workflowId       UNIQUEIDENTIFIER NULL,
    companyId        INT              NULL,
    service          VARCHAR(50)      NOT NULL,  -- stripe | azure_face | azure_blob | notification_hub | email | sms | document_intelligence
    operation        VARCHAR(100)     NULL,
    status           VARCHAR(30)      NULL,      -- SUCCESS | FAILED
    httpStatus       INT              NULL,
    latencyMs        INT              NULL,
    requestSummary   NVARCHAR(MAX)    NULL,      -- redacted + capped upstream
    responseSummary  NVARCHAR(MAX)    NULL,      -- redacted + capped upstream
    exception        NVARCHAR(MAX)    NULL,
    created_At       DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME()
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_integrationLogs_correlationId')
    CREATE INDEX IX_integrationLogs_correlationId ON [dbo].[integrationLogs] (correlationId);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_integrationLogs_service_time')
    CREATE INDEX IX_integrationLogs_service_time  ON [dbo].[integrationLogs] (service, created_At);
GO

-- ============================================================
-- Single-row insert SPs (durable path — one call per row)
-- All take a single-element JSON array in @pjsonfile, matching the
-- @pjsonfile convention SafeCursor rewrites for large NVARCHAR(MAX).
-- ============================================================

IF OBJECT_ID('dbo.sp_workflowLog', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_workflowLog;
GO
CREATE PROCEDURE [dbo].[sp_workflowLog] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO [dbo].[workflowLogs]
            (workflowId, correlationId, companyId, clientId, userId, entityName, entityId,
             workflowName, stepName, actionName, status, message, durationMs,
             requestJson, responseJson, exception, ipAddress, deviceInfo, appVersion, apiEndpoint)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.userId')),
            JSON_VALUE(value, '$.entityName'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.entityId')),
            JSON_VALUE(value, '$.workflowName'),
            JSON_VALUE(value, '$.stepName'),
            JSON_VALUE(value, '$.actionName'),
            JSON_VALUE(value, '$.status'),
            JSON_VALUE(value, '$.message'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.durationMs')),
            JSON_VALUE(value, '$.requestJson'),
            JSON_VALUE(value, '$.responseJson'),
            JSON_VALUE(value, '$.exception'),
            JSON_VALUE(value, '$.ipAddress'),
            JSON_VALUE(value, '$.deviceInfo'),
            JSON_VALUE(value, '$.appVersion'),
            JSON_VALUE(value, '$.apiEndpoint')
        FROM OPENJSON(@pjsonfile, '$.logs')
        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

IF OBJECT_ID('dbo.sp_auditLog', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_auditLog;
GO
CREATE PROCEDURE [dbo].[sp_auditLog] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO [dbo].[auditLogs]
            (correlationId, companyId, actorUserId, actorClientId, entityName, entityId,
             fieldName, oldValue, newValue, action, ipAddress, deviceInfo)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.actorUserId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.actorClientId')),
            JSON_VALUE(value, '$.entityName'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.entityId')),
            JSON_VALUE(value, '$.fieldName'),
            JSON_VALUE(value, '$.oldValue'),
            JSON_VALUE(value, '$.newValue'),
            JSON_VALUE(value, '$.action'),
            JSON_VALUE(value, '$.ipAddress'),
            JSON_VALUE(value, '$.deviceInfo')
        FROM OPENJSON(@pjsonfile, '$.logs')
        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

IF OBJECT_ID('dbo.sp_applicationLog', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_applicationLog;
GO
CREATE PROCEDURE [dbo].[sp_applicationLog] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO [dbo].[applicationLogs]
            (correlationId, workflowId, companyId, [level], source, message, exception,
             apiEndpoint, httpStatus, durationMs, ipAddress)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            ISNULL(JSON_VALUE(value, '$.level'), 'INFO'),
            JSON_VALUE(value, '$.source'),
            JSON_VALUE(value, '$.message'),
            JSON_VALUE(value, '$.exception'),
            JSON_VALUE(value, '$.apiEndpoint'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.httpStatus')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.durationMs')),
            JSON_VALUE(value, '$.ipAddress')
        FROM OPENJSON(@pjsonfile, '$.logs')
        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

IF OBJECT_ID('dbo.sp_integrationLog', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_integrationLog;
GO
CREATE PROCEDURE [dbo].[sp_integrationLog] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO [dbo].[integrationLogs]
            (correlationId, workflowId, companyId, service, operation, status, httpStatus,
             latencyMs, requestSummary, responseSummary, exception)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            JSON_VALUE(value, '$.service'),
            JSON_VALUE(value, '$.operation'),
            JSON_VALUE(value, '$.status'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.httpStatus')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.latencyMs')),
            JSON_VALUE(value, '$.requestSummary'),
            JSON_VALUE(value, '$.responseSummary'),
            JSON_VALUE(value, '$.exception')
        FROM OPENJSON(@pjsonfile, '$.logs')
        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_observability_logBatch  — async writer path
-- Accepts a mixed JSON array; each element has a "logType" of
-- workflow | audit | application | integration. Fans out into the
-- four tables in a single round trip.
-- ============================================================
IF OBJECT_ID('dbo.sp_observability_logBatch', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_observability_logBatch;
GO
CREATE PROCEDURE [dbo].[sp_observability_logBatch] @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- workflow
        INSERT INTO [dbo].[workflowLogs]
            (workflowId, correlationId, companyId, clientId, userId, entityName, entityId,
             workflowName, stepName, actionName, status, message, durationMs,
             requestJson, responseJson, exception, ipAddress, deviceInfo, appVersion, apiEndpoint)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.userId')),
            JSON_VALUE(value, '$.entityName'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.entityId')),
            JSON_VALUE(value, '$.workflowName'),
            JSON_VALUE(value, '$.stepName'),
            JSON_VALUE(value, '$.actionName'),
            JSON_VALUE(value, '$.status'),
            JSON_VALUE(value, '$.message'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.durationMs')),
            JSON_VALUE(value, '$.requestJson'),
            JSON_VALUE(value, '$.responseJson'),
            JSON_VALUE(value, '$.exception'),
            JSON_VALUE(value, '$.ipAddress'),
            JSON_VALUE(value, '$.deviceInfo'),
            JSON_VALUE(value, '$.appVersion'),
            JSON_VALUE(value, '$.apiEndpoint')
        FROM OPENJSON(@pjsonfile, '$.logs') WHERE JSON_VALUE(value, '$.logType') = 'workflow';

        -- application
        INSERT INTO [dbo].[applicationLogs]
            (correlationId, workflowId, companyId, [level], source, message, exception,
             apiEndpoint, httpStatus, durationMs, ipAddress)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            ISNULL(JSON_VALUE(value, '$.level'), 'INFO'),
            JSON_VALUE(value, '$.source'),
            JSON_VALUE(value, '$.message'),
            JSON_VALUE(value, '$.exception'),
            JSON_VALUE(value, '$.apiEndpoint'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.httpStatus')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.durationMs')),
            JSON_VALUE(value, '$.ipAddress')
        FROM OPENJSON(@pjsonfile, '$.logs') WHERE JSON_VALUE(value, '$.logType') = 'application';

        -- integration
        INSERT INTO [dbo].[integrationLogs]
            (correlationId, workflowId, companyId, service, operation, status, httpStatus,
             latencyMs, requestSummary, responseSummary, exception)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.workflowId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            JSON_VALUE(value, '$.service'),
            JSON_VALUE(value, '$.operation'),
            JSON_VALUE(value, '$.status'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.httpStatus')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.latencyMs')),
            JSON_VALUE(value, '$.requestSummary'),
            JSON_VALUE(value, '$.responseSummary'),
            JSON_VALUE(value, '$.exception')
        FROM OPENJSON(@pjsonfile, '$.logs') WHERE JSON_VALUE(value, '$.logType') = 'integration';

        -- audit (also accepted via batch when non-critical; durable path uses sp_auditLog)
        INSERT INTO [dbo].[auditLogs]
            (correlationId, companyId, actorUserId, actorClientId, entityName, entityId,
             fieldName, oldValue, newValue, action, ipAddress, deviceInfo)
        SELECT
            TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.correlationId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.actorUserId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.actorClientId')),
            JSON_VALUE(value, '$.entityName'),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.entityId')),
            JSON_VALUE(value, '$.fieldName'),
            JSON_VALUE(value, '$.oldValue'),
            JSON_VALUE(value, '$.newValue'),
            JSON_VALUE(value, '$.action'),
            JSON_VALUE(value, '$.ipAddress'),
            JSON_VALUE(value, '$.deviceInfo')
        FROM OPENJSON(@pjsonfile, '$.logs') WHERE JSON_VALUE(value, '$.logType') = 'audit';

        SELECT '{"message":"ok"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
