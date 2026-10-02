-- =============================================================================
-- Fix sp_income_monthly: DATEADD(HOUR, ...) on a DATE value
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: POST /monthly_income (the /dashboard income load) returns 500 since
-- 2026-09-30_income_terminal_commission.sql ran:
--   "The datepart hour is not supported by date function dateadd for data
--    type date." (error 9810, verified in production 2026-09-30)
-- DATEFROMPARTS() returns DATE, and DATEADD(HOUR, 7, <date>) is illegal.
-- The line came from 2026-09-29_income_monthly_any_month.sql (never run in
-- prod on its own) and was carried into the commission migration.
--
-- FIX: CAST(DATEFROMPARTS(...) AS DATETIME) before adding the 7 hours
-- (Hermosillo UTC-7 month start -> UTC). Nothing else changes: same columns,
-- including commissionTerminalId / commissionRatePct / commissionAmount.
-- Both earlier files are patched the same way so a replay cannot bring the
-- bug back.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_income_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT, @year INT, @month INT;

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @year      = TRY_CONVERT(INT, JSON_VALUE(value, '$.year')),
        @month     = TRY_CONVERT(INT, JSON_VALUE(value, '$.month'))
    FROM OPENJSON(@pjsonfile, '$.income');

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    IF @year IS NULL OR @month IS NULL OR @month NOT BETWEEN 1 AND 12 OR @year NOT BETWEEN 2000 AND 2100
    BEGIN
        SET @year  = YEAR(@HermosilloNow);
        SET @month = MONTH(@HermosilloNow);
    END

    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, CAST(DATEFROMPARTS(@year, @month, 1) AS DATETIME));
    DECLARE @MonthEndUtc   DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);

    IF EXISTS (
        SELECT 1 FROM [dbo].[income]
        WHERE companyId = @companyId
          AND paymentDate >= @MonthStartUtc
          AND paymentDate < @MonthEndUtc
    )
    BEGIN
        SELECT
            i.incomeId,
            i.orderId,
            i.total,
            i.paymentMethod,
            i.paymentDate,
            i.userId,
            i.clientId,
            i.companyId,
            ISNULL(i.discountAmount,0) AS discountAmount,
            i.commissionTerminalId,
            i.commissionRatePct,
            ISNULL(i.commissionAmount,0) AS commissionAmount
        FROM [dbo].[income] i
        WHERE i.companyId = @companyId
          AND i.paymentDate >= @MonthStartUtc
          AND i.paymentDate < @MonthEndUtc
        FOR JSON AUTO, ROOT('income');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [income]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
GO
