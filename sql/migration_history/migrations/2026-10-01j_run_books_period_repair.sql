-- =============================================================================
-- Step 7 — REPAIR the books period (2026-09-01 onward), explicitly
-- =============================================================================
-- Run ONLY after:
--   - 2026-09-30_fix_expense_paymentdate_midnight.sql  (expense dates; checked below)
--   - 2026-10-01e_backfill_income_commissions_sp.sql   (Step 4 SP; checked below)
--   - 2026-10-01g_income_reverse_on_delete.sql         (Step 5 SP; checked below)
--   - 2026-10-01i_reconcile_and_backfill_movements.sql + its test → ALL PASS
--
-- Order (each part idempotent; nothing is ever updated except status→VOID):
--   1. BEFORE: reconciliation summary
--   2. Post every income/expense in the period that has NO entry at all
--      (sp_journalEntries_backfillMovements, Step 3 map, Hermosillo dates)
--   3. Post the card commissions of sales that now have an income entry
--      (sp_journalEntries_backfillIncomeCommissions, Step 4)
--   4. Deleted sales whose entries are still POSTED → sp_income_reverseOnDelete
--      (VOID + points reversal — owner decision for deleted sales, Step 5)
--   5. AFTER: reconciliation summary + detail of what remains
-- Remaining after the run, by design (NOT auto-repaired — decide explicitly):
--   VOID_MISMATCH, AMOUNT_MISMATCH, DATE_MISMATCH (posted entries are immutable;
--   legacy income entries dated with the UTC day), COMPANY_MISMATCH,
--   DUPLICATE_JOURNAL, expense ORPHAN_JOURNAL.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── Pre-checks ───────────────────────────────────────────────────────────────
DECLARE @midnightExpenses INT = (
    SELECT COUNT(*) FROM dbo.expenses
    WHERE paymentDate >= '2026-08-31' AND CAST(paymentDate AS TIME) = '00:00:00');
SELECT @midnightExpenses AS expensesStillAtUtcMidnight,
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillIncomeCommissions', 'P') IS NOT NULL THEN 1 ELSE 0 END AS step4SpPresent,
       CASE WHEN OBJECT_ID('dbo.sp_income_reverseOnDelete', 'P') IS NOT NULL THEN 1 ELSE 0 END AS step5SpPresent,
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillMovements', 'P') IS NOT NULL THEN 1 ELSE 0 END AS step7SpPresent;

IF @midnightExpenses > 0
   OR OBJECT_ID('dbo.sp_journalEntries_backfillIncomeCommissions', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_income_reverseOnDelete', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_journalEntries_backfillMovements', 'P') IS NULL
BEGIN
    RAISERROR('Prerequisites missing (midnight expense fix / Step 4, 5 or 7 SP) — nothing was posted.', 16, 1);
    SET NOEXEC ON;
END
GO

-- ── 1. BEFORE ────────────────────────────────────────────────────────────────
CREATE TABLE #rec (issueType NVARCHAR(30), companyId INT, referenceType NVARCHAR(30), referenceId INT,
                   movementAmount DECIMAL(12,2), journalAmount DECIMAL(12,2), movementDate DATE, journalDate DATE);
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';
SELECT 'BEFORE' AS phase, companyId, issueType, referenceType, COUNT(*) AS issues,
       SUM(movementAmount) AS movementAmount, SUM(journalAmount) AS journalAmount
FROM #rec GROUP BY companyId, issueType, referenceType ORDER BY companyId, issueType, referenceType;

-- ── 2. Missing income / expense postings ─────────────────────────────────────
EXEC dbo.sp_journalEntries_backfillMovements @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 0;

-- ── 3. Commissions of sales that now have an income entry ────────────────────
EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 0;

-- ── 4. Deleted sales still counted → VOID + reverse points ───────────────────
DELETE FROM #rec;
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';
DECLARE @orphanIncome INT;
DECLARE oc CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT referenceId FROM #rec
    WHERE issueType = 'ORPHAN_JOURNAL' AND referenceType IN ('income', 'income_commission');
OPEN oc; FETCH NEXT FROM oc INTO @orphanIncome;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_income_reverseOnDelete @incomeId = @orphanIncome;
    FETCH NEXT FROM oc INTO @orphanIncome;
END
CLOSE oc; DEALLOCATE oc;

-- ── 5. AFTER ─────────────────────────────────────────────────────────────────
DELETE FROM #rec;
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';
SELECT 'AFTER' AS phase, companyId, issueType, referenceType, COUNT(*) AS issues,
       SUM(movementAmount) AS movementAmount, SUM(journalAmount) AS journalAmount
FROM #rec GROUP BY companyId, issueType, referenceType ORDER BY companyId, issueType, referenceType;

-- Gate: these must be 0 after the repair.
SELECT
    SUM(CASE WHEN issueType = 'MISSING_JOURNAL' THEN 1 ELSE 0 END)    AS missingJournal,
    SUM(CASE WHEN issueType = 'MISSING_COMMISSION' THEN 1 ELSE 0 END) AS missingCommission,
    SUM(CASE WHEN issueType = 'ORPHAN_JOURNAL' AND referenceType <> 'expense' THEN 1 ELSE 0 END) AS incomeOrphans
FROM #rec;

-- Detail of what remains for explicit decisions.
SELECT * FROM #rec ORDER BY companyId, issueType, referenceType, referenceId;

-- Operational vs journal for company 1, books period (totals should now agree
-- except for remaining AMOUNT/VOID/DUPLICATE items listed above).
SELECT 'operational' AS source,
       (SELECT ISNULL(SUM(total), 0) FROM dbo.income   WHERE companyId = 1 AND CAST(DATEADD(HOUR,-7,paymentDate) AS DATE) >= '2026-09-01') AS income,
       (SELECT ISNULL(SUM(total), 0) FROM dbo.expenses WHERE companyId = 1 AND CAST(DATEADD(HOUR,-7,paymentDate) AS DATE) >= '2026-09-01') AS expenses
UNION ALL
SELECT 'journal',
       (SELECT ISNULL(SUM(totalDebit), 0) FROM dbo.journalEntries WHERE companyId = 1 AND status = 'POSTED' AND referenceType = 'income'  AND entryDate >= '2026-09-01'),
       (SELECT ISNULL(SUM(totalDebit), 0) FROM dbo.journalEntries WHERE companyId = 1 AND status = 'POSTED' AND referenceType = 'expense' AND entryDate >= '2026-09-01');
DROP TABLE #rec;
GO

SET NOEXEC OFF;
GO
