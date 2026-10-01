-- =============================================================================
-- Step 4 — RUN the commission backfill (real posting) + reconciliation
-- =============================================================================
-- Run ONLY after:
--   1. 2026-10-01e_backfill_income_commissions_sp.sql   (SP created, dry run shown)
--   2. tests/2026-10-01e_backfill_income_commissions_test.sql → ALL CHECKS PASS
-- Posts Dr 5120 / Cr 1105 for every stamped card sale (books from 2026-09-01)
-- that has a POSTED income entry and no commission entry yet, all companies.
-- Idempotent: running it again posts 0. Never updates or deletes anything.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ── BEFORE ───────────────────────────────────────────────────────────────────
SELECT 'BEFORE' AS phase, e.companyId,
       COUNT(*) AS commissionEntries, ISNULL(SUM(e.totalDebit), 0) AS commissionAmount
FROM dbo.journalEntries e
WHERE e.referenceType = 'income_commission' AND e.status = 'POSTED'
GROUP BY e.companyId;

-- ── RUN ──────────────────────────────────────────────────────────────────────
EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 0;
GO

-- ── RECONCILIATION (per company, books from 2026-09-01) ──────────────────────
-- stampedWithIncomeEntry must equal commissionEntries, and the amounts must match.
SELECT i.companyId,
       COUNT(*)                                   AS stampedWithIncomeEntry,
       SUM(i.commissionAmount)                    AS stampedCommission,
       SUM(CASE WHEN c.entryId IS NOT NULL THEN 1 ELSE 0 END) AS commissionEntries,
       ISNULL(SUM(c.totalDebit), 0)               AS journaledCommission,
       SUM(CASE WHEN c.entryId IS NULL THEN 1 ELSE 0 END)     AS missing,
       SUM(CASE WHEN c.entryId IS NOT NULL AND c.totalDebit <> i.commissionAmount THEN 1 ELSE 0 END) AS amountMismatch
FROM dbo.income i
JOIN dbo.journalEntries ie
  ON ie.companyId = i.companyId AND ie.referenceType = 'income' AND ie.referenceId = i.incomeId
 AND ie.status = 'POSTED' AND ie.entryDate >= '2026-09-01'
LEFT JOIN dbo.journalEntries c
  ON c.companyId = i.companyId AND c.referenceType = 'income_commission' AND c.referenceId = i.incomeId
 AND c.status = 'POSTED'
WHERE i.commissionAmount > 0
GROUP BY i.companyId
ORDER BY i.companyId;

-- Duplicates (expect 0 rows).
SELECT companyId, referenceId AS incomeId, COUNT(*) AS postedCommissionEntries
FROM dbo.journalEntries
WHERE referenceType = 'income_commission' AND status = 'POSTED'
GROUP BY companyId, referenceId
HAVING COUNT(*) > 1;

-- Stamped card sales since 2026-09-01 with NO income entry (left for Step 7/10).
SELECT i.companyId, COUNT(*) AS salesWithoutIncomeEntry, SUM(i.total) AS salesTotal, SUM(i.commissionAmount) AS commission
FROM dbo.income i
WHERE i.commissionAmount > 0
  AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= '2026-09-01'
  AND NOT EXISTS (SELECT 1 FROM dbo.journalEntries e
                  WHERE e.companyId = i.companyId AND e.referenceType = 'income'
                    AND e.referenceId = i.incomeId AND e.status = 'POSTED')
GROUP BY i.companyId;

-- Re-run proof (expect candidates 0, posted 0).
EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
GO
