-- =============================================================================
-- sp_expense_all + sp_expense_monthly — also return serviceId
-- =============================================================================
-- NOT YET EXECUTED against any database -- run manually against the live DB.
--
-- WHY: 2026-10-01l_add_expense_service.sql added expenses.serviceId and
-- sp_expense now saves it (verified live: expense 1003 has serviceId = 3), but
-- explicitly left these two SELECT lists unchanged (see its KNOWN LIMITATION
-- note). Result: GET /all_expense and the month view never return serviceId,
-- so the Egresos list can't show WHICH service a 'general' expense paid
-- (Renta, CFE, Internet...) and falls back to the generic type label "General".
--
-- WHAT: adds e.serviceId to both SELECT lists. Nothing else changes — bodies
-- below are the LIVE definitions (read from the DB 2026-10-02, not the
-- repo's drifted copies) plus that one column. The frontend resolves the id to
-- a name the same way it already does for supplierId/employeeId.
-- Idempotent: CREATE OR ALTER. Rollback = re-run without e.serviceId.
-- =============================================================================

CREATE OR ALTER PROC [dbo].[sp_expense_all]
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM [dbo].[expenses])
    BEGIN
        SELECT
            e.expenseId,
            e.orderId,
            e.total,
            e.paymentMethod,
            e.paymentDate,
            e.userId,
            e.supplierId,
            e.serviceId,
            e.companyId,
            e.expenseType,
            e.employeeId,
            e.notes,
            e.receiptUrl
        FROM [dbo].[expenses] e
        FOR JSON AUTO, ROOT('expenses');
    END
    ELSE
    BEGIN
        SELECT '[]' AS [expenses]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
    END
END
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
                e.serviceId,
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
