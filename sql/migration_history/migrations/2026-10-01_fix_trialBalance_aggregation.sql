-- =============================================================================
-- Fix sp_journalEntries_trialBalance: per-account totals counted VOID entries
-- and entries after toDate
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 1 (§7.6).
-- Test:    sql/tests/2026-10-01_trialBalance_cutoff_test.sql (run it BEFORE this
--          script to see the bug — FAIL rows — and AFTER it to see all PASS).
--
-- WHY: the previous body filtered status/date in the ON clause of a LEFT JOIN:
--     LEFT JOIN journalEntryLines l ON l.accountId = a.accountId
--     LEFT JOIN journalEntries   e ON e.entryId = l.journalEntryId
--                                 AND e.status = 'POSTED' AND e.entryDate <= @toDate
--     ... SUM(l.debit), SUM(l.credit)
-- A VOID or post-cutoff entry only nulls `e`; its lines `l` are still summed,
-- so per-account debit/credit included them while the grand totals (computed
-- separately with a WHERE) did not. Balance General must be built on a correct
-- aggregation, so this is fixed first.
--
-- FIX: aggregate lines in a derived table that INNER JOINs only the company's
-- POSTED entries up to @toDate, then LEFT JOIN accounts to it. Same parameters,
-- same output shape (accountsJson / totalDebit / totalCredit / balanced), so
-- modules/journalEntries.py and the frontend need no change.
-- Behavior change (intended): rows that only had VOID/future activity no longer
-- appear; per-account sums now always add up to the grand totals.
--
-- Idempotent: CREATE OR ALTER. sql/sp_journalEntries.sql carries the same body
-- so a replay of the base script cannot bring the bug back.
-- Rollback:  re-run the previous body from git history of sql/sp_journalEntries.sql
--            (not recommended — it is the buggy one).
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_trialBalance]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT  = JSON_VALUE(@pjsonfile, '$.journalEntries[0].companyId')
    DECLARE @toDate    DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.journalEntries[0].toDate'))

    -- Lines of this company's POSTED entries up to the cutoff — the only lines
    -- any accounting report may count.
    DECLARE @accountsJson NVARCHAR(MAX) = (
        SELECT a.accountId, a.code AS accountCode, a.name AS accountName, a.accountType,
               a.normalBalance,
               m.debitTotal,
               m.creditTotal
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
        ORDER BY a.code
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

-- Verify the deployed body is the fixed one (expect 1).
SELECT CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries_trialBalance'))
                 LIKE '%GROUP BY l.accountId%' THEN 1 ELSE 0 END AS trialBalanceFixedDeployed;
GO
