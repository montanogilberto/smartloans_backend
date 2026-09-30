-- =============================================================================
-- dbo.sp_income_monthly — any month, not only the current one
-- =============================================================================
-- Forward-only, additive. NOT YET EXECUTED — run manually against the live DB.
--
-- WHY: /ingresos (IncomesPage) loaded GET /all_income → dbo.sp_income_all,
-- which has NO companyId filter: every company's income rows (770+) went to
-- every company's staff, and its "Total Mensual" mixed companies (it disagreed
-- with /movements: $29,090 / 139 vs $28,880 / 138 for September 2026).
-- /ingresos now reads one company + one month through this SP instead.
--
-- CHANGE: optional "year" and "month" in the payload. Omitted → the current
-- Hermosillo month, exactly as before (Dashboard and /movements unchanged):
--   {"income":[{"companyId": 1}]}                           -- current month
--   {"income":[{"companyId": 1, "year": 2026, "month": 8}]} -- August 2026
-- Month boundaries are Hermosillo local time (UTC-7, no DST) converted back
-- to UTC, same as the original version. Same output shape.
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

    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, DATEFROMPARTS(@year, @month, 1));
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
            ISNULL(i.discountAmount,0) AS discountAmount
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
