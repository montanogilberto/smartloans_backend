-- =============================================================================
-- Step 8 — Balance General (Estado de Situación Financiera) — read projection
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB, AFTER
-- 2026-10-01b_journal_accountTotals_fn.sql (uses fn_journalEntries_accountTotals).
-- Roadmap: POSVending/docs/accounting-module.md, Step 8 (§8).
-- Test:    sql/tests/2026-10-01k_balance_sheet_test.sql
-- API:     POST /journalEntries/balance-sheet (modules/journalEntries.py)
--
-- No new table, no stored balance: everything is computed from the journal
-- through dbo.fn_journalEntries_accountTotals (POSTED only, entryDate <= cutoff,
-- one company, signed by naturaleza) — the same aggregation as the Balanza.
--
-- OBJECTS
--   fn_journalEntries_balanceSheet(@companyId, @asOfDate)        inline TVF
--     one row per report line: section, grp, accountId, code, name, balance
--       ASSET     current (11xx and any other 1xxx) | nonCurrent (12xx)
--       LIABILITY current (21xx and any other 2xxx) | nonCurrent (22xx)
--       EQUITY    accounts
--       RESULT    priorYears  = Σ income − Σ expense, entryDate < Jan 1 of @asOfDate's year
--                 currentYear = Σ income − Σ expense, Jan 1 … @asOfDate
--     Accounts with a zero balance are omitted. No closing entries are needed:
--     income/expense are never zeroed; once real closing entries exist they
--     post to 3205/3210 and appear as equity accounts.
--   fn_journalEntries_balanceSheetJson(@companyId, @asOfDate)    scalar → JSON
--     { companyId, asOfDate,
--       assets:      { current:[{code,name,balance}], nonCurrent:[…], total },
--       liabilities: { current:[…], nonCurrent:[…], total },
--       equity:      { accounts:[…], priorYearsResult, currentYearResult, total },
--       totalLiabilitiesAndEquity, balanced }
--     balanced = ROUND(assets.total,2) = ROUND(totalLiabilitiesAndEquity,2)
--   sp_journalEntries_balanceSheet @pjsonfile
--     { "journalEntries":[{ "companyId":1, "asOfDate":"2026-09-30", "compareDate"?:"2025-12-31" }] }
--     asOfDate defaults to today in Hermosillo (UTC-7). With compareDate the
--     response gets "comparison": { same shape at compareDate }.
--     Returns one row/one column [jsonResult]; {"error":…} on bad input.
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[fn_journalEntries_balanceSheet]
(
    @companyId INT,
    @asOfDate  DATE
)
RETURNS TABLE
AS
RETURN
(
    WITH t AS (
        SELECT * FROM [dbo].[fn_journalEntries_accountTotals](@companyId, @asOfDate)
    ),
    priorYears AS (
        SELECT * FROM [dbo].[fn_journalEntries_accountTotals](@companyId, DATEADD(DAY, -1, DATEFROMPARTS(YEAR(@asOfDate), 1, 1)))
    )
    SELECT 'ASSET' AS section,
           CASE WHEN code LIKE '12%' THEN 'nonCurrent' ELSE 'current' END AS grp,
           accountId, code, name, balance
    FROM t WHERE accountType = 'ASSET' AND balance <> 0
    UNION ALL
    SELECT 'LIABILITY',
           CASE WHEN code LIKE '22%' THEN 'nonCurrent' ELSE 'current' END,
           accountId, code, name, balance
    FROM t WHERE accountType = 'LIABILITY' AND balance <> 0
    UNION ALL
    SELECT 'EQUITY', 'accounts', accountId, code, name, balance
    FROM t WHERE accountType = 'EQUITY' AND balance <> 0
    UNION ALL
    SELECT 'RESULT', 'priorYears', NULL, NULL, N'Resultados de ejercicios anteriores',
           ISNULL((SELECT SUM(CASE accountType WHEN 'INCOME' THEN balance ELSE -balance END)
                   FROM priorYears WHERE accountType IN ('INCOME', 'EXPENSE')), 0)
    UNION ALL
    SELECT 'RESULT', 'currentYear', NULL, NULL, N'Resultado del ejercicio',
           ISNULL((SELECT SUM(CASE accountType WHEN 'INCOME' THEN balance ELSE -balance END)
                   FROM t WHERE accountType IN ('INCOME', 'EXPENSE')), 0)
         - ISNULL((SELECT SUM(CASE accountType WHEN 'INCOME' THEN balance ELSE -balance END)
                   FROM priorYears WHERE accountType IN ('INCOME', 'EXPENSE')), 0)
);
GO

CREATE OR ALTER FUNCTION [dbo].[fn_journalEntries_balanceSheetJson]
(
    @companyId INT,
    @asOfDate  DATE
)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @lines TABLE (section NVARCHAR(10), grp NVARCHAR(12), code NVARCHAR(20), name NVARCHAR(150), balance DECIMAL(14,2));
    INSERT INTO @lines (section, grp, code, name, balance)
    SELECT section, grp, code, name, balance FROM [dbo].[fn_journalEntries_balanceSheet](@companyId, @asOfDate);

    DECLARE @assets DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'ASSET'), 0);
    DECLARE @liabilities DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'LIABILITY'), 0);
    DECLARE @equityAccounts DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'EQUITY'), 0);
    DECLARE @prior DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'RESULT' AND grp = 'priorYears'), 0);
    DECLARE @current DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM @lines WHERE section = 'RESULT' AND grp = 'currentYear'), 0);
    DECLARE @equity DECIMAL(14,2) = @equityAccounts + @prior + @current;

    RETURN (
        SELECT
            @companyId AS companyId,
            CONVERT(NVARCHAR(10), @asOfDate, 23) AS asOfDate,
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'ASSET' AND grp = 'current' ORDER BY code FOR JSON PATH), '[]')) AS [assets.current],
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'ASSET' AND grp = 'nonCurrent' ORDER BY code FOR JSON PATH), '[]')) AS [assets.nonCurrent],
            @assets AS [assets.total],
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'LIABILITY' AND grp = 'current' ORDER BY code FOR JSON PATH), '[]')) AS [liabilities.current],
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'LIABILITY' AND grp = 'nonCurrent' ORDER BY code FOR JSON PATH), '[]')) AS [liabilities.nonCurrent],
            @liabilities AS [liabilities.total],
            JSON_QUERY(ISNULL((SELECT code, name, balance FROM @lines WHERE section = 'EQUITY' ORDER BY code FOR JSON PATH), '[]')) AS [equity.accounts],
            @prior AS [equity.priorYearsResult],
            @current AS [equity.currentYearResult],
            @equity AS [equity.total],
            @liabilities + @equity AS totalLiabilitiesAndEquity,
            CAST(CASE WHEN ROUND(@assets, 2) = ROUND(@liabilities + @equity, 2) THEN 1 ELSE 0 END AS BIT) AS balanced
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_balanceSheet]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @companyId   INT  = TRY_CONVERT(INT,  JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId'));
    DECLARE @asOfRaw     NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].asOfDate');
    DECLARE @compareRaw  NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.journalEntries[0].compareDate');
    DECLARE @asOfDate    DATE = TRY_CONVERT(DATE, @asOfRaw);
    DECLARE @compareDate DATE = TRY_CONVERT(DATE, @compareRaw);

    IF @companyId IS NULL OR NOT EXISTS (SELECT 1 FROM [dbo].[companies] WHERE companyId = @companyId)
    BEGIN
        SELECT N'{"error":"companyId es requerido y debe existir."}' AS [jsonResult];
        RETURN;
    END
    IF (@asOfRaw IS NOT NULL AND @asOfDate IS NULL) OR (@compareRaw IS NOT NULL AND @compareDate IS NULL)
    BEGIN
        SELECT N'{"error":"asOfDate/compareDate deben ser fechas YYYY-MM-DD."}' AS [jsonResult];
        RETURN;
    END

    -- Default cutoff: today in Hermosillo (UTC-7, no DST).
    SET @asOfDate = ISNULL(@asOfDate, CAST(DATEADD(HOUR, -7, GETUTCDATE()) AS DATE));

    DECLARE @json NVARCHAR(MAX) = [dbo].[fn_journalEntries_balanceSheetJson](@companyId, @asOfDate);
    IF @compareDate IS NOT NULL
        SET @json = JSON_MODIFY(@json, '$.comparison',
                                JSON_QUERY([dbo].[fn_journalEntries_balanceSheetJson](@companyId, @compareDate)));

    SELECT @json AS [jsonResult];
END
GO

-- Verify (expect 1, 1, 1).
SELECT CASE WHEN OBJECT_ID('dbo.fn_journalEntries_balanceSheet', 'IF') IS NOT NULL THEN 1 ELSE 0 END AS balanceSheetFn,
       CASE WHEN OBJECT_ID('dbo.fn_journalEntries_balanceSheetJson', 'FN') IS NOT NULL THEN 1 ELSE 0 END AS balanceSheetJsonFn,
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_balanceSheet', 'P') IS NOT NULL THEN 1 ELSE 0 END AS balanceSheetSp;
GO
