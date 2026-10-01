-- =============================================================================
-- Step 4 — journal the card-terminal commissions (backfill procedure)
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 4 (§7.1).
-- Test:    sql/tests/2026-10-01e_backfill_income_commissions_test.sql
-- Run:     sql/migrations/2026-10-01f_run_income_commission_backfill.sql (after the test passes)
-- Live:    new card sales are journaled by modules/income.py →
--          post_income_commission_journal_entry (Dr 5120 / Cr 1105).
--
-- WHY: income.commissionAmount (4.2% card terminal, 2026-09-30 migration) is
-- stored per sale but was never journaled, so Bancos was overstated by every
-- commission and 5120 Comisiones bancarias stayed empty.
--
-- WHAT: dbo.sp_journalEntries_backfillIncomeCommissions
--   @companyId INT  = NULL          -- NULL = every company
--   @fromDate  DATE = '2026-09-01'  -- books open 2026-09-01 (owner decision Q1)
--   @dryRun    BIT  = 1             -- 1 = report only, 0 = post
-- Posts ONE entry per sale:  Dr 5120 Comisiones bancarias / Cr 1105 Bancos,
--   amount = income.commissionAmount, referenceType 'income_commission',
--   referenceId = incomeId, entryDate = the sale's own POSTED income entry date
--   (same day as the sale in the journal).
-- Only sales that ALREADY have a POSTED income entry dated >= @fromDate.
--   A sale without one is counted (skippedNoIncomeEntry) and NOT posted:
--   booking its commission alone would push Bancos below reality; those sales
--   are handled together with their income in Step 7/10 reconciliation.
-- Idempotent: skips sales that already have a POSTED 'income_commission' entry
--   (same rule as the sp_journalEntries duplicate guard), checked inside the
--   transaction under UPDLOCK/HOLDLOCK. Never updates or deletes anything.
-- Transactions: commits its own work when called alone; inside a caller's
--   transaction it uses a savepoint (so the rolled-back test can call it).
-- Returns ONE plain row (no FOR JSON, so tests can INSERT…EXEC it):
--   dryRun, candidates, posted, postedAmount, skippedNoIncomeEntry, skippedMissingAccount
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_backfillIncomeCommissions]
    @companyId INT  = NULL,
    @fromDate  DATE = '2026-09-01',
    @dryRun    BIT  = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @c TABLE (
        companyId INT, incomeId INT, amount DECIMAL(12,2), entryDate DATE,
        drAccountId INT NULL, crAccountId INT NULL
    );
    DECLARE @posted INT = 0, @postedAmount DECIMAL(14,2) = 0;
    DECLARE @tc INT = @@TRANCOUNT;

    BEGIN TRY
        IF @dryRun = 0
        BEGIN
            IF @tc = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION bfIncomeCommissions;
            -- Serialize with live posts: nobody may add entries for these
            -- companies while we decide what is missing and number the folios.
            DECLARE @lock INT = (SELECT COUNT(*) FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                                 WHERE @companyId IS NULL OR companyId = @companyId);
        END

        -- Candidates: stamped sales with a POSTED income entry on/after the
        -- opening date and no POSTED commission entry yet.
        INSERT INTO @c (companyId, incomeId, amount, entryDate, drAccountId, crAccountId)
        SELECT i.companyId, i.incomeId, i.commissionAmount, ie.entryDate,
               a5120.accountId, a1105.accountId
        FROM [dbo].[income] i
        CROSS APPLY (
            SELECT TOP 1 e.entryDate
            FROM [dbo].[journalEntries] e
            WHERE e.companyId = i.companyId AND e.referenceType = 'income'
              AND e.referenceId = i.incomeId AND e.status = 'POSTED'
            ORDER BY e.entryId
        ) ie
        LEFT JOIN [dbo].[chartOfAccounts] a5120
            ON a5120.companyId = i.companyId AND a5120.code = '5120' AND a5120.isPostable = 1 AND a5120.isActive = 1
        LEFT JOIN [dbo].[chartOfAccounts] a1105
            ON a1105.companyId = i.companyId AND a1105.code = '1105' AND a1105.isPostable = 1 AND a1105.isActive = 1
        WHERE (@companyId IS NULL OR i.companyId = @companyId)
          AND i.commissionAmount > 0
          AND ie.entryDate >= @fromDate
          AND NOT EXISTS (SELECT 1 FROM [dbo].[journalEntries] x
                          WHERE x.companyId = i.companyId AND x.referenceType = 'income_commission'
                            AND x.referenceId = i.incomeId AND x.status = 'POSTED');

        IF @dryRun = 0
        BEGIN
            DECLARE @max TABLE (companyId INT PRIMARY KEY, maxNum INT);
            INSERT INTO @max (companyId, maxNum)
            SELECT d.companyId,
                   ISNULL((SELECT MAX(entryNumber) FROM [dbo].[journalEntries] WHERE companyId = d.companyId), 0)
            FROM (SELECT DISTINCT companyId FROM @c WHERE drAccountId IS NOT NULL AND crAccountId IS NOT NULL) d;

            DECLARE @map TABLE (entryId INT, companyId INT, incomeId INT);

            INSERT INTO [dbo].[journalEntries]
                (companyId, entryNumber, entryDate, description, referenceType, referenceId,
                 status, totalDebit, totalCredit, createdByUserId)
            OUTPUT inserted.entryId, inserted.companyId, inserted.referenceId INTO @map (entryId, companyId, incomeId)
            SELECT c.companyId,
                   m.maxNum + ROW_NUMBER() OVER (PARTITION BY c.companyId ORDER BY c.entryDate, c.incomeId),
                   c.entryDate,
                   N'Comisión terminal ingreso #' + CAST(c.incomeId AS NVARCHAR(12)) + N' (backfill)',
                   'income_commission', c.incomeId, 'POSTED', c.amount, c.amount, NULL
            FROM @c c
            JOIN @max m ON m.companyId = c.companyId
            WHERE c.drAccountId IS NOT NULL AND c.crAccountId IS NOT NULL;

            INSERT INTO [dbo].[journalEntryLines] (journalEntryId, accountId, debit, credit, lineDescription)
            SELECT mp.entryId, c.drAccountId, c.amount, 0, N'Comisión terminal (backfill)'
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.incomeId = mp.incomeId
            UNION ALL
            SELECT mp.entryId, c.crAccountId, 0, c.amount, N'Comisión terminal (backfill)'
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.incomeId = mp.incomeId;

            SELECT @posted = COUNT(*), @postedAmount = ISNULL(SUM(c.amount), 0)
            FROM @map mp JOIN @c c ON c.companyId = mp.companyId AND c.incomeId = mp.incomeId;

            IF @tc = 0 COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @tc = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF @tc > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION bfIncomeCommissions;
        THROW;
    END CATCH

    SELECT
        @dryRun AS dryRun,
        (SELECT COUNT(*) FROM @c WHERE drAccountId IS NOT NULL AND crAccountId IS NOT NULL) AS candidates,
        @posted AS posted,
        @postedAmount AS postedAmount,
        (SELECT COUNT(*) FROM [dbo].[income] i
         WHERE (@companyId IS NULL OR i.companyId = @companyId)
           AND i.commissionAmount > 0
           AND CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) >= @fromDate
           AND NOT EXISTS (SELECT 1 FROM [dbo].[journalEntries] e
                           WHERE e.companyId = i.companyId AND e.referenceType = 'income'
                             AND e.referenceId = i.incomeId AND e.status = 'POSTED')) AS skippedNoIncomeEntry,
        (SELECT COUNT(*) FROM @c WHERE drAccountId IS NULL OR crAccountId IS NULL) AS skippedMissingAccount;
END
GO

-- Verify (expect 1) + a DRY RUN over every company (posts nothing).
SELECT CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillIncomeCommissions', 'P') IS NOT NULL THEN 1 ELSE 0 END AS backfillSpDeployed;
EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
GO
