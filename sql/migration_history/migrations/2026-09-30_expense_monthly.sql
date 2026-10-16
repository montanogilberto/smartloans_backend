-- =============================================================================
-- dbo.sp_expense_monthly — one company, one month (+ 12-month totals)
-- =============================================================================
-- Forward-only, additive. NOT YET EXECUTED — run manually against the live DB,
-- AFTER 2026-09-30_expense_all_return_new_columns.sql (same column list;
-- expenseType/employeeId/notes/receiptUrl must exist on dbo.expenses).
--
-- WHY: /egresos and the /dashboard "Egresos" KPIs loaded GET /all_expense →
-- sp_expense_all, which has NO companyId filter: every company's expense
-- history went to every company's staff, and the dashboard's daily/monthly
-- expense KPIs summed all companies. Same leak /ingresos had (fixed by
-- sp_income_monthly, 2026-09-29_income_monthly_any_month.sql).
--
-- PAYLOAD: optional year/month; omitted or invalid → current Hermosillo month.
--   {"expenses":[{"companyId": 1}]}                           -- current month
--   {"expenses":[{"companyId": 1, "year": 2026, "month": 8}]} -- August 2026
-- Month boundaries are Hermosillo local time (UTC-7, no DST) converted to UTC,
-- same as sp_income_monthly. DATEFROMPARTS is CAST to DATETIME before the
-- DATEADD(HOUR) — see 2026-09-30_fix_income_monthly_dateadd.sql.
--
-- RETURNS one JSON document:
--   { "expenses":      [ ...rows of the month, newest first... ],
--     "monthlyTotals": [ {year, month, total, count} for the 12 months ending
--                        at the requested month, months with rows only ] }
-- An empty month returns "expenses": [] (never NULL). JSON_QUERY keeps the
-- ISNULL'd subqueries as nested JSON instead of escaped strings.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROC [dbo].[sp_expense_monthly] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT, @year INT, @month INT;

    SELECT TOP 1
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @year      = TRY_CONVERT(INT, JSON_VALUE(value, '$.year')),
        @month     = TRY_CONVERT(INT, JSON_VALUE(value, '$.month'))
    FROM OPENJSON(@pjsonfile, '$.expenses');

    DECLARE @HermosilloNow DATETIME = DATEADD(HOUR, -7, GETUTCDATE());
    IF @year IS NULL OR @month IS NULL OR @month NOT BETWEEN 1 AND 12 OR @year NOT BETWEEN 2000 AND 2100
    BEGIN
        SET @year  = YEAR(@HermosilloNow);
        SET @month = MONTH(@HermosilloNow);
    END

    DECLARE @MonthStartUtc DATETIME = DATEADD(HOUR, 7, CAST(DATEFROMPARTS(@year, @month, 1) AS DATETIME));
    DECLARE @MonthEndUtc   DATETIME = DATEADD(MONTH, 1, @MonthStartUtc);
    DECLARE @TrendStartUtc DATETIME = DATEADD(MONTH, -11, @MonthStartUtc);

    SELECT
        JSON_QUERY(ISNULL((
            SELECT
                e.expenseId,
                e.orderId,
                e.total,
                e.paymentMethod,
                e.paymentDate,
                e.userId,
                e.supplierId,
                e.companyId,
                e.expenseType,
                e.employeeId,
                e.notes,
                e.receiptUrl
            FROM [dbo].[expenses] e
            WHERE e.companyId = @companyId
              AND e.paymentDate >= @MonthStartUtc
              AND e.paymentDate <  @MonthEndUtc
            ORDER BY e.paymentDate DESC
            FOR JSON PATH
        ), '[]')) AS [expenses],
        JSON_QUERY(ISNULL((
            SELECT
                YEAR(h.localDate)  AS [year],
                MONTH(h.localDate) AS [month],
                SUM(h.total)       AS [total],
                COUNT(*)           AS [count]
            FROM (
                SELECT DATEADD(HOUR, -7, e.paymentDate) AS localDate, e.total
                FROM [dbo].[expenses] e
                WHERE e.companyId = @companyId
                  AND e.paymentDate >= @TrendStartUtc
                  AND e.paymentDate <  @MonthEndUtc
            ) h
            GROUP BY YEAR(h.localDate), MONTH(h.localDate)
            ORDER BY [year], [month]
            FOR JSON PATH
        ), '[]')) AS [monthlyTotals]
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO
