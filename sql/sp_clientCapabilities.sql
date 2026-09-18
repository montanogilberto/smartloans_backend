-- ============================================================
-- clientCapabilities — the multi-valued "clientTypes" concept:
-- which GMO applications/capabilities a dbo.clients row
-- participates in (POS, SmartLoans Lender/Borrower/Juridical,
-- Rewards, Arcade). A client may hold any combination.
--
-- Deliberately separate from dbo.clients.clientType (singular,
-- pre-existing, lending-role label: lawyer|both|lender|borrower|pos)
-- -- that column is left untouched. This table does not replace it,
-- rename it, or migrate data out of it; the two are maintained
-- independently. See the optional one-time backfill at the bottom
-- of this file for seeding clientCapabilities from clientType.
--
-- Not gated by any authoritative reward balance -- purely a
-- classification/eligibility table, consumed by staff UI (client
-- badges/filters), the chat agent (capability-based intent routing),
-- and a future client self-login flow. Does not replace or gate
-- roleCode/canAccess staff authorization.
--
-- Run this single file once against the target DB (table uses
-- IF NOT EXISTS, procedure DROP+CREATE, safe to re-run).
-- ============================================================

-- ── Table: clientCapabilities ───────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'clientCapabilities')
CREATE TABLE [dbo].[clientCapabilities] (
    clientCapabilityId INT IDENTITY PRIMARY KEY,
    companyId           INT            NOT NULL,
    clientId             INT            NOT NULL,
    capability           NVARCHAR(30)   NOT NULL,  -- POS | SMARTLOANS_LENDER | SMARTLOANS_BORROWER | SMARTLOANS_JURIDICAL | REWARDS | ARCADE
    isActive             BIT            NOT NULL DEFAULT 1,
    created_At           DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at           DATETIME2      NULL,
    CONSTRAINT CK_clientCapabilities_capability CHECK (
        capability IN ('POS','SMARTLOANS_LENDER','SMARTLOANS_BORROWER','SMARTLOANS_JURIDICAL','REWARDS','ARCADE')
    )
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_clientCapabilities_company_client_capability')
    CREATE UNIQUE INDEX UQ_clientCapabilities_company_client_capability
        ON [dbo].[clientCapabilities] (companyId, clientId, capability);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_clientCapabilities_company_active')
    CREATE INDEX IX_clientCapabilities_company_active
        ON [dbo].[clientCapabilities] (companyId, capability, isActive);
GO

-- ── Stored Procedure: sp_clientCapabilities ─────────────────
-- action 0 (default) — read: { "clientCapabilities": [{ "companyId": int, "clientId"?: int, "capability"?: str }] }
-- action 1 — grant (insert if absent, reactivate if previously revoked):
--   { "clientCapabilities": [{ "action": 1, "companyId": int, "clientId": int, "capability": str }] }
-- action 2 — revoke (soft: isActive = 0, never deletes the row):
--   { "clientCapabilities": [{ "action": 2, "companyId": int, "clientId": int, "capability": str }] }
-- action 3 — rejected; capabilities are never hard-deleted (same convention as posRewardProductRates).
IF OBJECT_ID('dbo.sp_clientCapabilities', 'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_clientCapabilities]
GO
CREATE PROCEDURE [dbo].[sp_clientCapabilities]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.clientCapabilities[0].action'));
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.clientCapabilities[0].companyId'));

    BEGIN TRY
        IF @action IN (1,2)
        BEGIN
            DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.clientCapabilities[0].clientId'));
            DECLARE @capability NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.clientCapabilities[0].capability');

            IF @companyId IS NULL OR @clientId IS NULL OR @capability IS NULL
                RAISERROR('companyId, clientId y capability son requeridos.', 16, 1);

            IF NOT EXISTS (SELECT 1 FROM [dbo].[clients] WHERE clientId = @clientId AND companyId = @companyId)
                RAISERROR('clientId no pertenece a companyId.', 16, 1);

            IF @action = 1
            BEGIN
                MERGE [dbo].[clientCapabilities] AS tgt
                USING (SELECT @companyId AS companyId, @clientId AS clientId, @capability AS capability) AS src
                    ON tgt.companyId = src.companyId AND tgt.clientId = src.clientId AND tgt.capability = src.capability
                WHEN MATCHED THEN UPDATE SET
                    isActive = 1,
                    updated_at = GETUTCDATE()
                WHEN NOT MATCHED THEN
                    INSERT (companyId, clientId, capability, isActive)
                    VALUES (@companyId, @clientId, @capability, 1);
            END
            ELSE
            BEGIN
                UPDATE [dbo].[clientCapabilities]
                    SET isActive = 0, updated_at = GETUTCDATE()
                    WHERE companyId = @companyId AND clientId = @clientId AND capability = @capability;
            END

            DECLARE @rowJson NVARCHAR(MAX) = (
                SELECT clientCapabilityId, companyId, clientId, capability, isActive
                FROM [dbo].[clientCapabilities]
                WHERE companyId = @companyId AND clientId = @clientId AND capability = @capability
                FOR JSON PATH
            );
            SELECT ('{"result":[{"clientCapabilities":' + ISNULL(@rowJson, '[]') + ',"msg":"OK","error":"0"}]}') AS [jsonResult]
        END
        ELSE IF @action = 3
            RAISERROR('clientCapabilities never hard-deletes -- use action=2 (revoke).', 16, 1);
        ELSE
        BEGIN
            -- action 0 / read
            DECLARE @clientIdFilter INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.clientCapabilities[0].clientId'));
            DECLARE @capabilityFilter NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.clientCapabilities[0].capability');

            IF @companyId IS NULL
                RAISERROR('companyId es requerido.', 16, 1);

            DECLARE @listJson NVARCHAR(MAX) = (
                SELECT clientCapabilityId, companyId, clientId, capability, isActive, created_At, updated_at
                FROM [dbo].[clientCapabilities]
                WHERE companyId = @companyId
                  AND (@clientIdFilter IS NULL OR clientId = @clientIdFilter)
                  AND (@capabilityFilter IS NULL OR capability = @capabilityFilter)
                ORDER BY clientId, capability
                FOR JSON PATH
            );
            SELECT ('{"result":[{"clientCapabilities":' + ISNULL(@listJson, '[]') + '}]}') AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- OPTIONAL one-time backfill — seeds clientCapabilities from the
-- existing dbo.clients.clientType column. Additive only (inserts
-- rows that don't already exist); does not modify or clear
-- clientType. Safe to run once after the table above exists; safe
-- to re-run (idempotent via NOT EXISTS). Not executed by this file
-- automatically -- run manually, same convention as
-- sql/migrations/2026-09-14_add_pos_client_type.sql.
-- ============================================================
-- INSERT INTO [dbo].[clientCapabilities] (companyId, clientId, capability)
-- SELECT c.companyId, c.clientId, cap.capability
-- FROM [dbo].[clients] c
-- CROSS APPLY (
--     SELECT 'SMARTLOANS_LENDER' AS capability WHERE c.clientType IN ('lender','both')
--     UNION ALL SELECT 'SMARTLOANS_BORROWER' WHERE c.clientType IN ('borrower','both')
--     UNION ALL SELECT 'POS' WHERE c.clientType = 'pos'
-- ) cap
-- WHERE NOT EXISTS (
--     SELECT 1 FROM [dbo].[clientCapabilities] cc
--     WHERE cc.companyId = c.companyId AND cc.clientId = c.clientId AND cc.capability = cap.capability
-- );
