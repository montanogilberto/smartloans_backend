-- =============================================================================
-- Redeploy sp_commissionTerminals / _all / _one against dbo.commissionTerminals
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: dbo.commission_terminals was renamed to dbo.commissionTerminals on
-- 2026-09-18. sql/sp_commissionTerminals.sql was updated for the rename but
-- never re-run, so the live SPs still read the old name and every
-- /commissionTerminals, /all_commissionTerminals, /one_commissionTerminals
-- call fails with "Invalid object name" (found 2026-09-30 via
-- sys.sql_expression_dependencies).
--
-- SCOPE: the three SP definitions only, copied verbatim from
-- sql/sp_commissionTerminals.sql. Deliberately NOT re-running that whole
-- file: its tail holds one-off data fixes (reset Mercado Pago to 4.2%,
-- backfill income.commissionTerminalId) that must not be replayed — the
-- rate reset would overwrite any change made since.
-- Idempotent: DROP-if-exists + CREATE, safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_commissionTerminals', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_commissionTerminals;
GO

CREATE PROCEDURE [dbo].[sp_commissionTerminals]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action               INT           = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].action')
        DECLARE @commissionTerminalId INT           = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].commissionTerminalId')
        DECLARE @provider             VARCHAR(40)   = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].provider')
        DECLARE @terminalName         VARCHAR(80)   = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].terminalName')
        DECLARE @paymentMethod        VARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].paymentMethod')
        DECLARE @country              CHAR(2)       = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].country')
        DECLARE @commissionRatePct    DECIMAL(6,3)  = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].commissionRatePct')
        DECLARE @fixedFeeAmount       DECIMAL(10,2) = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].fixedFeeAmount')
        DECLARE @currency             CHAR(3)       = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].currency')
        DECLARE @isActive             BIT           = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].isActive')
        DECLARE @validTo              DATETIME      = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].validTo')

        IF @action = 1 -- CREATE
        BEGIN
            IF @provider IS NULL OR @terminalName IS NULL OR @commissionRatePct IS NULL
                RAISERROR('provider, terminalName y commissionRatePct son requeridos.', 16, 1);

            INSERT INTO [dbo].[commissionTerminals]
                (provider, terminalName, paymentMethod, country, commissionRatePct, fixedFeeAmount, currency, isActive)
            VALUES
                (@provider, @terminalName, @paymentMethod, @country, @commissionRatePct, @fixedFeeAmount, @currency, ISNULL(@isActive, 1))

            SELECT (SELECT TOP 1 commissionTerminalId, provider, terminalName, paymentMethod, country,
                           commissionRatePct, fixedFeeAmount, currency, isActive,
                           CONVERT(NVARCHAR, validFrom, 127) AS validFrom,
                           CONVERT(NVARCHAR, createdAt, 127) AS createdAt
                    FROM [dbo].[commissionTerminals]
                    WHERE commissionTerminalId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE
        BEGIN
            IF @commissionTerminalId IS NULL
                RAISERROR('commissionTerminalId es requerido.', 16, 1);

            UPDATE [dbo].[commissionTerminals]
            SET provider           = ISNULL(@provider, provider),
                terminalName       = ISNULL(@terminalName, terminalName),
                paymentMethod      = ISNULL(@paymentMethod, paymentMethod),
                country            = ISNULL(@country, country),
                commissionRatePct  = ISNULL(@commissionRatePct, commissionRatePct),
                fixedFeeAmount     = ISNULL(@fixedFeeAmount, fixedFeeAmount),
                currency           = ISNULL(@currency, currency),
                isActive           = ISNULL(@isActive, isActive),
                validTo            = ISNULL(@validTo, validTo),
                updatedAt          = GETDATE()
            WHERE commissionTerminalId = @commissionTerminalId

            SELECT (SELECT TOP 1 commissionTerminalId, provider, terminalName, paymentMethod, country,
                           commissionRatePct, fixedFeeAmount, currency, isActive
                    FROM [dbo].[commissionTerminals]
                    WHERE commissionTerminalId = @commissionTerminalId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 3 -- DEACTIVATE (nunca DELETE — puede tener income ya referenciándola)
        BEGIN
            IF @commissionTerminalId IS NULL
                RAISERROR('commissionTerminalId es requerido.', 16, 1);

            UPDATE [dbo].[commissionTerminals]
            SET isActive = 0, updatedAt = GETDATE()
            WHERE commissionTerminalId = @commissionTerminalId

            SELECT '{"message":"deactivated","commissionTerminalId":' + CAST(@commissionTerminalId AS NVARCHAR(20)) + '}' AS [jsonResult]
        END

        ELSE
            SELECT '{"error":"Invalid action"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_commissionTerminals_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_commissionTerminals_all;
GO
CREATE PROCEDURE [dbo].[sp_commissionTerminals_all]
AS
BEGIN
    SET NOCOUNT ON;

    -- Devuelve TODAS las terminales (activas e inactivas); el frontend
    -- decide si oculta las inactivas, igual que chartOfAccounts.
    SELECT ISNULL(
        (SELECT commissionTerminalId, provider, terminalName, paymentMethod, country,
                commissionRatePct, fixedFeeAmount, currency, isActive,
                CONVERT(NVARCHAR, validFrom, 127) AS validFrom,
                CONVERT(NVARCHAR, validTo, 127)   AS validTo,
                CONVERT(NVARCHAR, createdAt, 127) AS createdAt
         FROM [dbo].[commissionTerminals]
         ORDER BY provider, terminalName
         FOR JSON PATH, ROOT('commissionTerminals')),
        '{"commissionTerminals":[]}'
    ) AS [jsonResult]
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_commissionTerminals_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_commissionTerminals_one;
GO
CREATE PROCEDURE [dbo].[sp_commissionTerminals_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @commissionTerminalId INT = JSON_VALUE(@pjsonfile, '$.commissionTerminals[0].commissionTerminalId')

    SELECT ISNULL(
        (SELECT TOP 1 commissionTerminalId, provider, terminalName, paymentMethod, country,
                commissionRatePct, fixedFeeAmount, currency, isActive,
                CONVERT(NVARCHAR, validFrom, 127) AS validFrom,
                CONVERT(NVARCHAR, createdAt, 127) AS createdAt
         FROM [dbo].[commissionTerminals]
         WHERE commissionTerminalId = @commissionTerminalId
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        '{}'
    ) AS [jsonResult]
END
GO
