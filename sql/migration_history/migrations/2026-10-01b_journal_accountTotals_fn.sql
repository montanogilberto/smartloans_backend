-- =============================================================================
-- Step 1b — one accounting aggregation for every report:
--   dbo.fn_journalEntries_accountTotals(@companyId, @toDate)
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB, AFTER
-- 2026-10-01_fix_trialBalance_aggregation.sql (already run: fixed body live).
-- Roadmap: POSVending/docs/accounting-module.md, Step 1.
-- Test:    sql/tests/2026-10-01_trialBalance_cutoff_test.sql
--
-- WHY: the Step 1 test could not capture sp_journalEntries_trialBalance's
-- output — SQL Server rejects INSERT…EXEC of a procedure that uses FOR JSON
-- ("The FOR JSON clause is not allowed in a INSERT statement"). Moving the
-- per-account aggregation into an inline table-valued function:
--   - makes it testable from plain T-SQL (SELECT … FROM the function);
--   - gives Balance General (Step 8) and Estado de Resultados (Step 11) the
--     SAME aggregation instead of a copy — one place to get cutoff/VOID right.
-- sp_journalEntries_trialBalance becomes a thin JSON wrapper over it; its
-- parameters and output shape do not change.
--
-- RULES (the only lines any accounting report may count):
--   journalEntries.companyId = @companyId AND status = 'POSTED'
--   AND (@toDate IS NULL OR entryDate <= @toDate)
--   accounts: same company, isPostable = 1, with non-zero activity.
--   balance = debit − credit (normalBalance 'D') | credit − debit ('C').
--
-- Idempotent: function and procedure use CREATE OR ALTER (SQL 2016 SP1+,
-- already used by earlier migrations). No table or data changes.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER FUNCTION [dbo].[fn_journalEntries_accountTotals]
(
    @companyId INT,
    @toDate    DATE   -- NULL = no cutoff
)
RETURNS TABLE
AS
RETURN
(
    SELECT a.accountId,
           a.code,
           a.name,
           a.accountType,
           a.normalBalance,
           a.parentAccountId,
           m.debitTotal,
           m.creditTotal,
           CASE WHEN a.normalBalance = 'D' THEN m.debitTotal - m.creditTotal
                ELSE m.creditTotal - m.debitTotal END AS balance
    FROM [dbo].[chartOfAccounts] a
    JOIN (
        SELECT l.accountId,
               SUM(l.debit)  AS debitTotal,
               SUM(l.credit) AS creditTotal
        FROM [dbo].[journalEntryLines] l
        JOIN [dbo].[journalEntries] e ON e.entryId = l.journalEntryId
        WHERE e.companyId = @companyId
          AND e.status = 'POSTED'
          AND (@toDate IS NULL OR e.entryDate <= @toDate)
        GROUP BY l.accountId
    ) m ON m.accountId = a.accountId
    WHERE a.companyId = @companyId
      AND a.isPostable = 1
      AND (m.debitTotal <> 0 OR m.creditTotal <> 0)
);
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_trialBalance]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT  = JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId')
    DECLARE @toDate    DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].toDate'))

    DECLARE @accountsJson NVARCHAR(MAX) = (
        SELECT t.accountId, t.code AS accountCode, t.name AS accountName, t.accountType,
               t.normalBalance, t.debitTotal, t.creditTotal
        FROM [dbo].[fn_journalEntries_accountTotals](@companyId, @toDate) t
        ORDER BY t.code
        FOR JSON PATH
    );

    DECLARE @totalDebit DECIMAL(14,2), @totalCredit DECIMAL(14,2);
    SELECT @totalDebit = ISNULL(SUM(l.debit), 0), @totalCredit = ISNULL(SUM(l.credit), 0)
    FROM [dbo].[journalEntryLines] l
    JOIN [dbo].[journalEntries] e ON e.entryId = l.journalEntryId
    WHERE e.companyId = @companyId AND e.status = 'POSTED'
      AND (@toDate IS NULL OR e.entryDate <= @toDate);

    SELECT
        ISNULL(@accountsJson, '[]') AS accountsJson,
        @totalDebit AS totalDebit,
        @totalCredit AS totalCredit,
        CASE WHEN ROUND(@totalDebit, 2) = ROUND(@totalCredit, 2) THEN 1 ELSE 0 END AS balanced
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
END
GO

-- Verify (expect 1, 1).
SELECT
    CASE WHEN OBJECT_ID('dbo.fn_journalEntries_accountTotals', 'IF') IS NOT NULL THEN 1 ELSE 0 END AS accountTotalsFnDeployed,
    CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries_trialBalance'))
              LIKE '%fn_journalEntries_accountTotals%' THEN 1 ELSE 0 END AS trialBalanceUsesFn;
GO
