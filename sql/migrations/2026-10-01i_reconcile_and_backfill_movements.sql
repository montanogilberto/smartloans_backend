-- =============================================================================
-- Step 7 — historical strategy: books from 2026-09-01 (Option A), reconciled
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 7 (§7.5).
-- Test:    sql/tests/2026-10-01i_reconcile_and_backfill_movements_test.sql
-- Repair:  sql/migrations/2026-10-01j_run_books_period_repair.sql (explicit run)
--
-- OWNER DECISION (Q1, 2026-10-01): Option A — formal books start 2026-09-01.
-- Movements before that date stay operational history and are NEVER posted.
-- Inside the books period every income/expense/commission must be in the
-- journal exactly once; today they are not (e.g. the income hook silently
-- never fired for a while — see modules/income.py — so ~$7,040 of company 1's
-- September income has no entry).
--
-- 1) dbo.sp_journalEntries_reconcileMovements  (READ-ONLY; reused by Step 10)
--    @companyId INT = NULL, @fromDate DATE = '2026-09-01', @toDate DATE = NULL
--    One plain row per issue (no FOR JSON → testable with INSERT…EXEC):
--      issueType, companyId, referenceType, referenceId, movementAmount,
--      journalAmount, movementDate, journalDate
--    issueType:
--      MISSING_JOURNAL     movement in period, no entry at all for it
--      VOID_MISMATCH       movement exists, but its only entries are VOID
--      MISSING_COMMISSION  card sale with commissionAmount and a POSTED income
--                          entry, but no POSTED commission entry
--      AMOUNT_MISMATCH     POSTED entry total <> movement amount
--      DATE_MISMATCH       entryDate <> the movement's Hermosillo date
--      DUPLICATE_JOURNAL   more than one POSTED entry for the same reference
--      ORPHAN_JOURNAL      POSTED entry whose movement no longer exists
--      COMPANY_MISMATCH    POSTED entry in another company than its movement
--    Movement date = Hermosillo date of paymentDate (UTC-7).
--
-- 2) dbo.sp_journalEntries_backfillMovements  (explicit repair, dry run default)
--    @companyId INT = NULL, @fromDate DATE = '2026-09-01', @dryRun BIT = 1
--    Posts ONLY MISSING_JOURNAL movements (no entry at all, POSTED or VOID),
--    with the same map as modules/journalEntries.py (Step 3):
--      income   Efectivo → Dr 1101 Caja, else Dr 1105 Bancos / Cr 4105
--      expense  Dr by type (payroll 5110, general 5115, inventory 5105)
--               Cr 1101 Caja (Efectivo) or 1105 Bancos
--    entryDate = Hermosillo date of paymentDate. referenceType income/expense +
--    referenceId → the Step 3 guard rule; idempotent (re-run posts 0).
--    VOID_MISMATCH rows are NOT re-posted (a VOID was a decision; review them).
--    Savepoint-aware; returns ONE plain row:
--      dryRun, incomeCandidates, expenseCandidates, posted, postedAmount, skippedMissingAccount
-- Nothing is ever updated or deleted by either procedure.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_reconcileMovements]
    @companyId INT  = NULL,
    @fromDate  DATE = '2026-09-01',
    @toDate    DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Movements in the books period (Hermosillo date).
    DECLARE @mov TABLE (refType NVARCHAR(30), refId INT, companyId INT, amount DECIMAL(12,2), movDate DATE);
    INSERT INTO @mov
    SELECT 'income', i.incomeId, i.companyId, i.total, CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE)
    FROM [dbo].[income] i
    WHERE (@companyId IS NULL OR i.companyId = @companyId)
      AND i.paymentDate IS NOT NULL
      AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= @fromDate
      AND (@toDate IS NULL OR CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) <= @toDate);
    INSERT INTO @mov
    SELECT 'income_commission', i.incomeId, i.companyId, i.commissionAmount, CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE)
    FROM [dbo].[income] i
    WHERE (@companyId IS NULL OR i.companyId = @companyId)
      AND i.commissionAmount > 0 AND i.paymentDate IS NOT NULL
      AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= @fromDate
      AND (@toDate IS NULL OR CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) <= @toDate);
    INSERT INTO @mov
    SELECT 'expense', x.expenseId, x.companyId, x.total, CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE)
    FROM [dbo].[expenses] x
    WHERE (@companyId IS NULL OR x.companyId = @companyId)
      AND x.paymentDate IS NOT NULL
      AND CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE) >= @fromDate
      AND (@toDate IS NULL OR CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE) <= @toDate);

    -- Movement-linked journal entries (any company, any status) for those references
    -- + every POSTED movement entry dated in the period (for orphans/duplicates).
    DECLARE @je TABLE (entryId INT, refType NVARCHAR(30), refId INT, companyId INT, status NVARCHAR(10), amount DECIMAL(12,2), entryDate DATE);
    INSERT INTO @je
    SELECT e.entryId, e.referenceType, e.referenceId, e.companyId, e.status, e.totalDebit, e.entryDate
    FROM [dbo].[journalEntries] e
    WHERE e.referenceType IN ('income', 'income_commission', 'expense') AND e.referenceId IS NOT NULL
      AND (
            EXISTS (SELECT 1 FROM @mov m WHERE m.refType = e.referenceType AND m.refId = e.referenceId)
         OR (    e.status = 'POSTED'
             AND (@companyId IS NULL OR e.companyId = @companyId)
             AND e.entryDate >= @fromDate AND (@toDate IS NULL OR e.entryDate <= @toDate))
      );

    DECLARE @issues TABLE (issueType NVARCHAR(30), companyId INT, referenceType NVARCHAR(30), referenceId INT,
                           movementAmount DECIMAL(12,2) NULL, journalAmount DECIMAL(12,2) NULL,
                           movementDate DATE NULL, journalDate DATE NULL);

    -- MISSING_COMMISSION (needs the sale's POSTED income entry) / MISSING_JOURNAL / VOID_MISMATCH
    INSERT INTO @issues (issueType, companyId, referenceType, referenceId, movementAmount, movementDate)
    SELECT CASE WHEN m.refType = 'income_commission' THEN 'MISSING_COMMISSION'
                WHEN EXISTS (SELECT 1 FROM @je j WHERE j.refType = m.refType AND j.refId = m.refId) THEN 'VOID_MISMATCH'
                ELSE 'MISSING_JOURNAL' END,
           m.companyId, m.refType, m.refId, m.amount, m.movDate
    FROM @mov m
    WHERE NOT EXISTS (SELECT 1 FROM @je j WHERE j.refType = m.refType AND j.refId = m.refId AND j.status = 'POSTED')
      AND (m.refType <> 'income_commission'
           OR EXISTS (SELECT 1 FROM @je j WHERE j.refType = 'income' AND j.refId = m.refId AND j.status = 'POSTED'));

    -- AMOUNT / DATE / COMPANY mismatches on POSTED entries of existing movements
    INSERT INTO @issues (issueType, companyId, referenceType, referenceId, movementAmount, journalAmount, movementDate, journalDate)
    SELECT 'COMPANY_MISMATCH', j.companyId, j.refType, j.refId, m.amount, j.amount, m.movDate, j.entryDate
    FROM @je j JOIN @mov m ON m.refType = j.refType AND m.refId = j.refId
    WHERE j.status = 'POSTED' AND j.companyId <> m.companyId
    UNION ALL
    SELECT 'AMOUNT_MISMATCH', j.companyId, j.refType, j.refId, m.amount, j.amount, m.movDate, j.entryDate
    FROM @je j JOIN @mov m ON m.refType = j.refType AND m.refId = j.refId
    WHERE j.status = 'POSTED' AND j.companyId = m.companyId AND j.amount <> m.amount
    UNION ALL
    SELECT 'DATE_MISMATCH', j.companyId, j.refType, j.refId, m.amount, j.amount, m.movDate, j.entryDate
    FROM @je j JOIN @mov m ON m.refType = j.refType AND m.refId = j.refId
    WHERE j.status = 'POSTED' AND j.companyId = m.companyId AND j.entryDate <> m.movDate;

    -- DUPLICATE_JOURNAL
    INSERT INTO @issues (issueType, companyId, referenceType, referenceId, journalAmount)
    SELECT 'DUPLICATE_JOURNAL', j.companyId, j.refType, j.refId, SUM(j.amount)
    FROM @je j WHERE j.status = 'POSTED'
    GROUP BY j.companyId, j.refType, j.refId
    HAVING COUNT(*) > 1;

    -- ORPHAN_JOURNAL (movement gone)
    INSERT INTO @issues (issueType, companyId, referenceType, referenceId, journalAmount, journalDate)
    SELECT 'ORPHAN_JOURNAL', j.companyId, j.refType, j.refId, j.amount, j.entryDate
    FROM @je j
    WHERE j.status = 'POSTED'
      AND (   (j.refType IN ('income', 'income_commission') AND NOT EXISTS (SELECT 1 FROM [dbo].[income] i WHERE i.incomeId = j.refId))
           OR (j.refType = 'expense' AND NOT EXISTS (SELECT 1 FROM [dbo].[expenses] x WHERE x.expenseId = j.refId)));

    SELECT issueType, companyId, referenceType, referenceId, movementAmount, journalAmount, movementDate, journalDate
    FROM @issues
    ORDER BY companyId, issueType, referenceType, referenceId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_backfillMovements]
    @companyId INT  = NULL,
    @fromDate  DATE = '2026-09-01',
    @dryRun    BIT  = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @c TABLE (companyId INT, refType NVARCHAR(30), refId INT, amount DECIMAL(12,2), entryDate DATE,
                      drCode NVARCHAR(20), crCode NVARCHAR(20), drAccountId INT NULL, crAccountId INT NULL);
    DECLARE @posted INT = 0, @postedAmount DECIMAL(14,2) = 0;
    DECLARE @tc INT = @@TRANCOUNT;

    BEGIN TRY
        IF @dryRun = 0
        BEGIN
            IF @tc = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION bfMovements;
            DECLARE @lock INT = (SELECT COUNT(*) FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                                 WHERE @companyId IS NULL OR companyId = @companyId);
        END

        -- Income with no journal entry at all (POSTED or VOID).
        INSERT INTO @c (companyId, refType, refId, amount, entryDate, drCode, crCode)
        SELECT i.companyId, 'income', i.incomeId, i.total, CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE),
               CASE WHEN LOWER(LTRIM(RTRIM(i.paymentMethod))) IN ('efectivo', 'cash') THEN '1101' ELSE '1105' END,
               '4105'
        FROM [dbo].[income] i
        WHERE (@companyId IS NULL OR i.companyId = @companyId)
          AND i.total > 0 AND i.paymentDate IS NOT NULL
          AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= @fromDate
          AND NOT EXISTS (SELECT 1 FROM [dbo].[journalEntries] e
                          WHERE e.referenceType = 'income' AND e.referenceId = i.incomeId);

        -- Expenses with no journal entry at all.
        INSERT INTO @c (companyId, refType, refId, amount, entryDate, drCode, crCode)
        SELECT x.companyId, 'expense', x.expenseId, x.total, CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE),
               CASE LOWER(ISNULL(NULLIF(LTRIM(RTRIM(x.expenseType)), ''), 'inventory'))
                    WHEN 'payroll' THEN '5110' WHEN 'general' THEN '5115' ELSE '5105' END,
               CASE WHEN LOWER(LTRIM(RTRIM(x.paymentMethod))) IN ('efectivo', 'cash') THEN '1101' ELSE '1105' END
        FROM [dbo].[expenses] x
        WHERE (@companyId IS NULL OR x.companyId = @companyId)
          AND x.total > 0 AND x.paymentDate IS NOT NULL
          AND CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE) >= @fromDate
          AND NOT EXISTS (SELECT 1 FROM [dbo].[journalEntries] e
                          WHERE e.referenceType = 'expense' AND e.referenceId = x.expenseId);

        UPDATE c SET
            drAccountId = (SELECT a.accountId FROM [dbo].[chartOfAccounts] a
                           WHERE a.companyId = c.companyId AND a.code = c.drCode AND a.isPostable = 1 AND a.isActive = 1),
            crAccountId = (SELECT a.accountId FROM [dbo].[chartOfAccounts] a
                           WHERE a.companyId = c.companyId AND a.code = c.crCode AND a.isPostable = 1 AND a.isActive = 1)
        FROM @c c;

        IF @dryRun = 0
        BEGIN
            DECLARE @max TABLE (companyId INT PRIMARY KEY, maxNum INT);
            INSERT INTO @max (companyId, maxNum)
            SELECT d.companyId,
                   ISNULL((SELECT MAX(entryNumber) FROM [dbo].[journalEntries] WHERE companyId = d.companyId), 0)
            FROM (SELECT DISTINCT companyId FROM @c WHERE drAccountId IS NOT NULL AND crAccountId IS NOT NULL) d;

            DECLARE @map TABLE (entryId INT, companyId INT, refType NVARCHAR(30), refId INT);

            INSERT INTO [dbo].[journalEntries]
                (companyId, entryNumber, entryDate, description, referenceType, referenceId,
                 status, totalDebit, totalCredit, createdByUserId)
            OUTPUT inserted.entryId, inserted.companyId, inserted.referenceType, inserted.referenceId
              INTO @map (entryId, companyId, refType, refId)
            SELECT c.companyId,
                   m.maxNum + ROW_NUMBER() OVER (PARTITION BY c.companyId ORDER BY c.entryDate, c.refType, c.refId),
                   c.entryDate,
                   CASE c.refType WHEN 'income' THEN N'Ingreso #' ELSE N'Egreso #' END
                       + CAST(c.refId AS NVARCHAR(12)) + N' (backfill)',
                   c.refType, c.refId, 'POSTED', c.amount, c.amount, NULL
            FROM @c c JOIN @max m ON m.companyId = c.companyId
            WHERE c.drAccountId IS NOT NULL AND c.crAccountId IS NOT NULL;

            INSERT INTO [dbo].[journalEntryLines] (journalEntryId, accountId, debit, credit, lineDescription)
            SELECT mp.entryId, c.drAccountId, c.amount, 0, N'Backfill libros 2026-09-01'
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.refType = mp.refType AND c.refId = mp.refId
            UNION ALL
            SELECT mp.entryId, c.crAccountId, 0, c.amount, N'Backfill libros 2026-09-01'
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.refType = mp.refType AND c.refId = mp.refId;

            SELECT @posted = COUNT(*), @postedAmount = ISNULL(SUM(c.amount), 0)
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.refType = mp.refType AND c.refId = mp.refId;

            IF @tc = 0 COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @tc = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF @tc > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION bfMovements;
        THROW;
    END CATCH

    SELECT @dryRun AS dryRun,
           (SELECT COUNT(*) FROM @c WHERE refType = 'income'  AND drAccountId IS NOT NULL AND crAccountId IS NOT NULL) AS incomeCandidates,
           (SELECT COUNT(*) FROM @c WHERE refType = 'expense' AND drAccountId IS NOT NULL AND crAccountId IS NOT NULL) AS expenseCandidates,
           @posted AS posted,
           @postedAmount AS postedAmount,
           (SELECT COUNT(*) FROM @c WHERE drAccountId IS NULL OR crAccountId IS NULL) AS skippedMissingAccount;
END
GO

-- ── Verify + READ-ONLY evidence (nothing is posted by this script) ───────────
SELECT CASE WHEN OBJECT_ID('dbo.sp_journalEntries_reconcileMovements', 'P') IS NOT NULL THEN 1 ELSE 0 END AS reconcileSpDeployed,
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillMovements', 'P') IS NOT NULL THEN 1 ELSE 0 END AS backfillMovementsSpDeployed;

CREATE TABLE #rec (issueType NVARCHAR(30), companyId INT, referenceType NVARCHAR(30), referenceId INT,
                   movementAmount DECIMAL(12,2), journalAmount DECIMAL(12,2), movementDate DATE, journalDate DATE);
INSERT INTO #rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';

-- Summary per company / issue (books since 2026-09-01).
SELECT companyId, issueType, referenceType, COUNT(*) AS issues,
       SUM(movementAmount) AS movementAmount, SUM(journalAmount) AS journalAmount
FROM #rec GROUP BY companyId, issueType, referenceType ORDER BY companyId, issueType, referenceType;

-- What the repair would post (dry run).
EXEC dbo.sp_journalEntries_backfillMovements @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
DROP TABLE #rec;
GO
