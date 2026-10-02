-- =============================================================================
-- Step 7 (cont.) — correct journal entries dated with the UTC day
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 7.
-- Test:    sql/tests/2026-10-01l_correct_entry_dates_test.sql
-- Run:     sql/migrations/2026-10-01m_run_correct_entry_dates.sql (explicit)
--
-- WHY: until 2026-10-01 the posting helper took the first 10 characters of the
-- POS cart's UTC timestamp as the entry date, so sales after 17:00 Hermosillo
-- were dated the NEXT day. Live reconciliation (company 1): 29 income + 15
-- commission entries; 3 sales of Sept 30 evening ($700, commissions $29.40)
-- landed in October. Owner decision (2026-10-01): correct ALL of them.
--
-- HOW (the plan's correction mechanism — nothing is deleted or edited):
--   for each POSTED entry with referenceType income | income_commission |
--   expense whose entryDate <> the Hermosillo date of its movement
--   (income/expenses.paymentDate − 7h; a commission uses its sale's date):
--     1. status → VOID
--     2. a new POSTED entry: same companyId, referenceType, referenceId,
--        totals and lines; entryDate = the correct date; new folio;
--        description + ' (fecha corregida)'.
--   Idempotent: corrected entries match their movement, so a re-run finds 0.
--   Only same-company movements (COMPANY_MISMATCH entries are left alone).
--   Savepoint-aware. Returns ONE plain row: dryRun, candidates, corrected, amount
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_journalEntries_correctDates]
    @companyId INT  = NULL,
    @fromDate  DATE = '2026-09-01',
    @dryRun    BIT  = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @c TABLE (entryId INT PRIMARY KEY, companyId INT, correctDate DATE, amount DECIMAL(12,2));
    DECLARE @corrected INT = 0, @amount DECIMAL(14,2) = 0;
    DECLARE @tc INT = @@TRANCOUNT;

    BEGIN TRY
        IF @dryRun = 0
        BEGIN
            IF @tc = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION correctDates;
            DECLARE @lock INT = (SELECT COUNT(*) FROM [dbo].[journalEntries] WITH (UPDLOCK, HOLDLOCK)
                                 WHERE @companyId IS NULL OR companyId = @companyId);
        END

        INSERT INTO @c (entryId, companyId, correctDate, amount)
        SELECT e.entryId, e.companyId, m.localDate, e.totalDebit
        FROM [dbo].[journalEntries] e
        CROSS APPLY (
            SELECT CAST(DATEADD(HOUR, -7, i.paymentDate) AS DATE) AS localDate, i.companyId
            FROM [dbo].[income] i
            WHERE e.referenceType IN ('income', 'income_commission') AND i.incomeId = e.referenceId
            UNION ALL
            SELECT CAST(DATEADD(HOUR, -7, x.paymentDate) AS DATE), x.companyId
            FROM [dbo].[expenses] x
            WHERE e.referenceType = 'expense' AND x.expenseId = e.referenceId
        ) m
        WHERE e.status = 'POSTED'
          AND e.referenceType IN ('income', 'income_commission', 'expense')
          AND (@companyId IS NULL OR e.companyId = @companyId)
          AND m.companyId = e.companyId
          AND m.localDate IS NOT NULL
          AND m.localDate >= @fromDate
          AND e.entryDate <> m.localDate;

        IF @dryRun = 0
        BEGIN
            DECLARE @max TABLE (companyId INT PRIMARY KEY, maxNum INT);
            INSERT INTO @max (companyId, maxNum)
            SELECT d.companyId, ISNULL((SELECT MAX(entryNumber) FROM [dbo].[journalEntries] WHERE companyId = d.companyId), 0)
            FROM (SELECT DISTINCT companyId FROM @c) d;

            UPDATE e SET status = 'VOID', updated_at = GETUTCDATE()
            FROM [dbo].[journalEntries] e JOIN @c c ON c.entryId = e.entryId;

            DECLARE @map TABLE (oldEntryId INT, newEntryId INT);

            -- MERGE (not INSERT…SELECT) so OUTPUT can pair each new entry with its original.
            MERGE [dbo].[journalEntries] AS tgt
            USING (
                SELECT e.entryId AS oldEntryId, e.companyId,
                       m.maxNum + ROW_NUMBER() OVER (PARTITION BY e.companyId ORDER BY c.correctDate, e.entryId) AS entryNumber,
                       c.correctDate, LEFT(e.description, 255 - 18) + N' (fecha corregida)' AS description,
                       e.referenceType, e.referenceId, e.totalDebit, e.totalCredit
                FROM @c c
                JOIN [dbo].[journalEntries] e ON e.entryId = c.entryId
                JOIN @max m ON m.companyId = e.companyId
            ) AS src
            ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (companyId, entryNumber, entryDate, description, referenceType, referenceId,
                        status, totalDebit, totalCredit, createdByUserId)
                VALUES (src.companyId, src.entryNumber, src.correctDate, src.description, src.referenceType,
                        src.referenceId, 'POSTED', src.totalDebit, src.totalCredit, NULL)
            OUTPUT src.oldEntryId, inserted.entryId INTO @map (oldEntryId, newEntryId);

            INSERT INTO [dbo].[journalEntryLines] (journalEntryId, accountId, debit, credit, lineDescription)
            SELECT mp.newEntryId, l.accountId, l.debit, l.credit, l.lineDescription
            FROM @map mp JOIN [dbo].[journalEntryLines] l ON l.journalEntryId = mp.oldEntryId;

            SELECT @corrected = COUNT(*) FROM @map;
            SELECT @amount = ISNULL(SUM(amount), 0) FROM @c;

            IF @tc = 0 COMMIT TRANSACTION;
        END
    END TRY
    BEGIN CATCH
        IF @tc = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF @tc > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION correctDates;
        THROW;
    END CATCH

    SELECT @dryRun AS dryRun, (SELECT COUNT(*) FROM @c) AS candidates, @corrected AS corrected,
           CASE WHEN @dryRun = 1 THEN (SELECT ISNULL(SUM(amount), 0) FROM @c) ELSE @amount END AS amount;
END
GO

SELECT CASE WHEN OBJECT_ID('dbo.sp_journalEntries_correctDates', 'P') IS NOT NULL THEN 1 ELSE 0 END AS correctDatesSpDeployed;
-- Dry run, all companies (posts nothing).
EXEC dbo.sp_journalEntries_correctDates @companyId = NULL, @fromDate = '2026-09-01', @dryRun = 1;
GO
