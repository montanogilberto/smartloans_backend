-- =============================================================================
-- Step 7 — RUN the date correction (explicit) + reconciliation
-- =============================================================================
-- Run ONLY after 2026-10-01l_correct_entry_dates.sql and its test → ALL PASS.
-- VOIDs every POSTED income / commission / expense entry dated with the wrong
-- (UTC) day and re-posts an identical copy on the Hermosillo day. Idempotent.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

EXEC dbo.sp_journalEntries_correctDates @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
EXEC dbo.sp_journalEntries_correctDates @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 0;
-- Re-run proof (expect candidates 0).
EXEC dbo.sp_journalEntries_correctDates @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;

CREATE TABLE #rec (issueType NVARCHAR(30), companyId INT, referenceType NVARCHAR(30), referenceId INT,
                   movementAmount DECIMAL(12,2), journalAmount DECIMAL(12,2), movementDate DATE, journalDate DATE);
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';
-- Expect NO rows (every movement in the books period posted once, right amount, right day).
SELECT companyId, issueType, referenceType, COUNT(*) AS issues FROM #rec
GROUP BY companyId, issueType, referenceType ORDER BY companyId, issueType;
DROP TABLE #rec;

-- Company 1, September (Hermosillo): operational vs journal must now be equal.
SELECT 'operational' AS source,
       (SELECT SUM(total) FROM dbo.income WHERE companyId = 1
          AND CAST(DATEADD(HOUR,-7,paymentDate) AS DATE) BETWEEN '2026-09-01' AND '2026-09-30') AS septIncome,
       (SELECT SUM(commissionAmount) FROM dbo.income WHERE companyId = 1
          AND CAST(DATEADD(HOUR,-7,paymentDate) AS DATE) BETWEEN '2026-09-01' AND '2026-09-30') AS septCommission
UNION ALL
SELECT 'journal',
       (SELECT SUM(totalDebit) FROM dbo.journalEntries WHERE companyId = 1 AND status = 'POSTED'
          AND referenceType = 'income' AND entryDate BETWEEN '2026-09-01' AND '2026-09-30'),
       (SELECT SUM(totalDebit) FROM dbo.journalEntries WHERE companyId = 1 AND status = 'POSTED'
          AND referenceType = 'income_commission' AND entryDate BETWEEN '2026-09-01' AND '2026-09-30');
GO
