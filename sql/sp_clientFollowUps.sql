-- ============================================================
-- clientFollowUps  — client monitoring / collections log
-- sp_clientFollowUps  (action 1=create, 2=update, 3=delete)
-- ============================================================
-- One row per follow-up event on a client. The credit engine
-- (sp_creditScore_data) COUNTs rows by riskStatus:
--   riskStatus = 'at_risk'  -> -8  per row to the score mix
--   riskStatus = 'default'  -> -20 per row (heavy penalty)
-- Only clientId, companyId and riskStatus are read by the score
-- engine today; the remaining columns support the follow-up UI.
-- ============================================================

-- ── Table: clientFollowUps_status (lookup / catalog) ────────
-- Created BEFORE clientFollowUps so the FK below can reference it.
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'clientFollowUps_status')
CREATE TABLE [dbo].[clientFollowUps_status] (
    riskStatus   NVARCHAR(20)   NOT NULL PRIMARY KEY,
    sortOrder    INT            NOT NULL,
    description  NVARCHAR(100)  NULL,
    scorePenalty INT            NOT NULL DEFAULT 0   -- mirrors creditScore.py weights
)
GO

-- Seed the catalog values (idempotent)
MERGE [dbo].[clientFollowUps_status] AS t
USING (VALUES
    ('on_track', 1, 'Client repaying as expected',            0),
    ('at_risk',  2, 'Showing early signs of repayment risk',  8),
    ('default',  3, 'Client in default on obligations',      20)
) AS s (riskStatus, sortOrder, description, scorePenalty)
ON t.riskStatus = s.riskStatus
WHEN NOT MATCHED THEN
    INSERT (riskStatus, sortOrder, description, scorePenalty)
    VALUES (s.riskStatus, s.sortOrder, s.description, s.scorePenalty);
GO

-- ── Table: clientFollowUps ──────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'clientFollowUps')
CREATE TABLE [dbo].[clientFollowUps] (
    followUpId    INT IDENTITY PRIMARY KEY,
    clientId      INT            NOT NULL,
    companyId     INT            NOT NULL,
    riskStatus    NVARCHAR(20)   NOT NULL DEFAULT 'on_track',
                  -- on_track | at_risk | default
    reason        NVARCHAR(200)  NULL,   -- why the flag was raised
    note          NVARCHAR(500)  NULL,   -- free-text follow-up note
    assignedTo    INT            NULL,   -- userId of the agent handling it
    dueDate       DATETIME2      NULL,   -- when the next follow-up is due
    resolvedAt    DATETIME2      NULL,   -- set when the follow-up is closed
    created_At    DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at    DATETIME2      NULL
)
GO

-- Indexes matching the read patterns in sp_creditScore_data + the follow-up UI
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_clientFollowUps_client_risk')
    CREATE INDEX IX_clientFollowUps_client_risk
        ON [dbo].[clientFollowUps] (companyId, clientId, riskStatus);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_clientFollowUps_company_due')
    CREATE INDEX IX_clientFollowUps_company_due
        ON [dbo].[clientFollowUps] (companyId, dueDate) INCLUDE (riskStatus);
GO

-- ── Relationship: clientFollowUps.riskStatus → clientFollowUps_status.riskStatus
IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_clientFollowUps_status')
    ALTER TABLE [dbo].[clientFollowUps]
        ADD CONSTRAINT FK_clientFollowUps_status
        FOREIGN KEY (riskStatus) REFERENCES [dbo].[clientFollowUps_status] (riskStatus);
GO

-- ============================================================
-- sp_clientFollowUps  (action 1=create, 2=update, 3=delete)
-- ============================================================
IF OBJECT_ID('dbo.sp_clientFollowUps', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_clientFollowUps;
GO

CREATE PROCEDURE [dbo].[sp_clientFollowUps]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action     INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].action')
        DECLARE @followUpId INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].followUpId')
        DECLARE @clientId   INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].clientId')
        DECLARE @companyId  INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].companyId')
        DECLARE @riskStatus NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].riskStatus'), 'on_track')
        DECLARE @reason     NVARCHAR(200) = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].reason')
        DECLARE @note       NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].note')
        DECLARE @assignedTo INT           = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].assignedTo')
        DECLARE @dueDate    DATETIME2     = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].dueDate')
        DECLARE @resolvedAt DATETIME2     = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].resolvedAt')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[clientFollowUps]
                (clientId, companyId, riskStatus, reason, note, assignedTo, dueDate)
            VALUES
                (@clientId, @companyId, @riskStatus, @reason, @note, @assignedTo, @dueDate)

            SELECT (SELECT TOP 1 followUpId, clientId, companyId, riskStatus,
                           reason, note, assignedTo,
                           CONVERT(NVARCHAR, dueDate, 127)    AS dueDate,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[clientFollowUps]
                    WHERE followUpId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (change risk / resolve / reassign)
        BEGIN
            UPDATE [dbo].[clientFollowUps]
            SET riskStatus  = ISNULL(@riskStatus, riskStatus),
                reason      = ISNULL(@reason, reason),
                note        = ISNULL(@note, note),
                assignedTo  = ISNULL(@assignedTo, assignedTo),
                dueDate     = ISNULL(@dueDate, dueDate),
                resolvedAt  = ISNULL(@resolvedAt, resolvedAt),
                updated_at  = GETUTCDATE()
            WHERE followUpId = @followUpId

            SELECT '{"message":"updated","followUpId":' + CAST(@followUpId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[clientFollowUps] WHERE followUpId = @followUpId
            SELECT '{"message":"deleted","followUpId":' + CAST(@followUpId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_clientFollowUps_all
-- ============================================================
IF OBJECT_ID('dbo.sp_clientFollowUps_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_clientFollowUps_all;
GO

CREATE PROCEDURE [dbo].[sp_clientFollowUps_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId  INT          = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].companyId')
        DECLARE @clientId   INT          = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].clientId')
        DECLARE @riskStatus NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].riskStatus')

        SELECT ISNULL(
            (SELECT followUpId, clientId, companyId, riskStatus,
                    reason, note, assignedTo,
                    CONVERT(NVARCHAR, dueDate, 127)    AS dueDate,
                    CONVERT(NVARCHAR, resolvedAt, 127) AS resolvedAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM [dbo].[clientFollowUps]
             WHERE companyId = @companyId
               AND (@clientId   IS NULL OR clientId   = @clientId)
               AND (@riskStatus IS NULL OR riskStatus = @riskStatus)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('clientFollowUps')),
            '{"clientFollowUps":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_clientFollowUps_one
-- ============================================================
IF OBJECT_ID('dbo.sp_clientFollowUps_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_clientFollowUps_one;
GO

CREATE PROCEDURE [dbo].[sp_clientFollowUps_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @followUpId INT = JSON_VALUE(@pjsonfile, '$.clientFollowUps[0].followUpId')

        SELECT ISNULL(
            (SELECT TOP 1 * FROM [dbo].[clientFollowUps]
             WHERE followUpId = @followUpId
             FOR JSON PATH, ROOT('clientFollowUps')),
            '{"clientFollowUps":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
