-- =============================================================================
-- TEST — Step 4: sp_journalEntries_backfillIncomeCommissions
-- Roadmap Step 4 gate (POSVending/docs/accounting-module.md §7.1)
-- =============================================================================
-- SAFE TO RUN ON PRODUCTION: one outer transaction, ALWAYS rolled back (the SP
-- uses a savepoint when called inside a transaction). Fake companies -9301 /
-- -9302; their income rows, accounts and journal entries vanish on rollback.
--
-- Company A (-9301), all sales $100, card commission 4.20 unless noted:
--   I1 card 2026-09-10, POSTED income entry                 -> backfilled
--   I2 card 2026-09-15, POSTED income + commission entries  -> skipped (already posted)
--   I3 card 2026-08-20, POSTED income entry (before books)  -> skipped (before fromDate)
--   I4 card 2026-09-20, NO income entry                     -> skippedNoIncomeEntry
--   I5 cash 2026-09-21, no commission                       -> not a candidate
--   I7 card 2026-09-22, income entry VOID                   -> skippedNoIncomeEntry
-- Company B (-9302):
--   I6 card 2026-09-12, commission 2.10, POSTED income      -> posted only by a B-scoped run
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @A INT = -9301, @B INT = -9302;
DECLARE @checks TABLE (seq INT IDENTITY, name NVARCHAR(200), expected NVARCHAR(80), actual NVARCHAR(80));
DECLARE @run TABLE (label NVARCHAR(10), dryRun BIT, candidates INT, posted INT, postedAmount DECIMAL(14,2),
                    skippedNoIncomeEntry INT, skippedMissingAccount INT);
DECLARE @out TABLE (dryRun BIT, candidates INT, posted INT, postedAmount DECIMAL(14,2),
                    skippedNoIncomeEntry INT, skippedMissingAccount INT);

INSERT INTO @checks (name, expected, actual)
SELECT N'backfill SP deployed', '1',
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillIncomeCommissions', 'P') IS NOT NULL THEN '1' ELSE '0' END;
IF OBJECT_ID('dbo.sp_journalEntries_backfillIncomeCommissions', 'P') IS NULL GOTO Report;

BEGIN TRANSACTION;
BEGIN TRY
    IF EXISTS (SELECT 1 FROM dbo.chartOfAccounts WHERE companyId IN (@A, @B))
        RAISERROR('Test companies -9301/-9302 already have accounts — aborting.', 16, 1);
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @A;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @B;

    -- ── Sales (paymentDate in UTC, 18:00Z = 11:00 Hermosillo, same day) ─────
    DECLARE @sales TABLE (tag NVARCHAR(5), companyId INT, method NVARCHAR(20), paidUtc DATETIME,
                          commission DECIMAL(10,2) NULL, incomeEntry NVARCHAR(10) NULL, entryDate DATE NULL,
                          hasCommissionEntry BIT, incomeId INT NULL);
    INSERT INTO @sales (tag, companyId, method, paidUtc, commission, incomeEntry, entryDate, hasCommissionEntry) VALUES
        ('I1', @A, 'Tarjeta',  '2026-09-10T18:00:00', 4.20, 'POSTED', '2026-09-10', 0),
        ('I2', @A, 'Tarjeta',  '2026-09-15T18:00:00', 4.20, 'POSTED', '2026-09-15', 1),
        ('I3', @A, 'Tarjeta',  '2026-08-20T18:00:00', 4.20, 'POSTED', '2026-08-20', 0),
        ('I4', @A, 'Tarjeta',  '2026-09-20T18:00:00', 4.20, NULL,     NULL,         0),
        ('I5', @A, 'Efectivo', '2026-09-21T18:00:00', NULL, 'POSTED', '2026-09-21', 0),
        ('I7', @A, 'Tarjeta',  '2026-09-22T18:00:00', 4.20, 'VOID',   '2026-09-22', 0),
        ('I6', @B, 'Tarjeta',  '2026-09-12T18:00:00', 2.10, 'POSTED', '2026-09-12', 0);

    DECLARE @tag NVARCHAR(5), @cid INT, @m NVARCHAR(20), @paid DATETIME, @com DECIMAL(10,2), @ie NVARCHAR(10),
            @ed DATE, @hc BIT, @incomeId INT, @num INT, @entryId INT;
    DECLARE s CURSOR LOCAL FAST_FORWARD FOR
        SELECT tag, companyId, method, paidUtc, commission, incomeEntry, entryDate, hasCommissionEntry FROM @sales;
    OPEN s;
    FETCH NEXT FROM s INTO @tag, @cid, @m, @paid, @com, @ie, @ed, @hc;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO dbo.income (total, paymentMethod, paymentDate, userId, clientId, companyId, commissionRatePct, commissionAmount)
        VALUES (100, @m, @paid, 0, 0, @cid, CASE WHEN @com IS NULL THEN NULL ELSE 4.2 END, @com);
        SET @incomeId = SCOPE_IDENTITY();
        UPDATE @sales SET incomeId = @incomeId WHERE tag = @tag;

        IF @ie IS NOT NULL
        BEGIN
            SELECT @num = ISNULL(MAX(entryNumber), 0) + 1 FROM dbo.journalEntries WHERE companyId = @cid;
            INSERT INTO dbo.journalEntries (companyId, entryNumber, entryDate, description, referenceType, referenceId, status, totalDebit, totalCredit)
            VALUES (@cid, @num, @ed, N'TEST income ' + @tag, 'income', @incomeId, @ie, 100, 100);
            SET @entryId = SCOPE_IDENTITY();
            INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
            SELECT @entryId, accountId, 100, 0 FROM dbo.chartOfAccounts
            WHERE companyId = @cid AND code = CASE WHEN @m = 'Efectivo' THEN '1101' ELSE '1105' END;
            INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
            SELECT @entryId, accountId, 0, 100 FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = '4105';
        END
        IF @hc = 1
        BEGIN
            SELECT @num = ISNULL(MAX(entryNumber), 0) + 1 FROM dbo.journalEntries WHERE companyId = @cid;
            INSERT INTO dbo.journalEntries (companyId, entryNumber, entryDate, description, referenceType, referenceId, status, totalDebit, totalCredit)
            VALUES (@cid, @num, @ed, N'TEST commission ' + @tag, 'income_commission', @incomeId, 'POSTED', @com, @com);
            SET @entryId = SCOPE_IDENTITY();
            INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
            SELECT @entryId, accountId, @com, 0 FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = '5120';
            INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
            SELECT @entryId, accountId, 0, @com FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = '1105';
        END
        FETCH NEXT FROM s INTO @tag, @cid, @m, @paid, @com, @ie, @ed, @hc;
    END
    CLOSE s; DEALLOCATE s;

    DECLARE @i1 INT = (SELECT incomeId FROM @sales WHERE tag='I1');
    DECLARE @i6 INT = (SELECT incomeId FROM @sales WHERE tag='I6');
    DECLARE @commA0 INT = (SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income_commission');

    -- ── R1 dry run, company A ────────────────────────────────────────────────
    DELETE FROM @out;
    INSERT INTO @out EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = @A, @fromDate = '2026-09-01', @dryRun = 1;
    INSERT INTO @run SELECT 'R1', * FROM @out;
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 dry run: candidates/posted/skippedNoIncomeEntry', '1/0/2',
        (SELECT CAST(candidates AS NVARCHAR(5)) + '/' + CAST(posted AS NVARCHAR(5)) + '/' + CAST(skippedNoIncomeEntry AS NVARCHAR(5)) FROM @run WHERE label='R1');
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 dry run wrote nothing', CAST(@commA0 AS NVARCHAR(5)),
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income_commission') AS NVARCHAR(5));

    -- ── R2 real run, company A ───────────────────────────────────────────────
    DELETE FROM @out;
    INSERT INTO @out EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = @A, @fromDate = '2026-09-01', @dryRun = 0;
    INSERT INTO @run SELECT 'R2', * FROM @out;
    INSERT INTO @checks (name, expected, actual) SELECT N'R2 posted / amount', '1/4.20',
        (SELECT CAST(posted AS NVARCHAR(5)) + '/' + CAST(postedAmount AS NVARCHAR(20)) FROM @run WHERE label='R2');
    INSERT INTO @checks (name, expected, actual) SELECT N'R2 entry for I1: type/date/status/totals', 'income_commission/2026-09-10/POSTED/4.20/4.20',
        ISNULL((SELECT referenceType + '/' + CONVERT(NVARCHAR(10), entryDate, 23) + '/' + status + '/'
                       + CAST(totalDebit AS NVARCHAR(20)) + '/' + CAST(totalCredit AS NVARCHAR(20))
                FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income_commission' AND referenceId=@i1), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'R2 I1 lines: Dr 5120 / Cr 1105', '5120:4.20:0.00|1105:0.00:4.20',
        ISNULL((SELECT STUFF((SELECT '|' + a.code + ':' + CAST(l.debit AS NVARCHAR(20)) + ':' + CAST(l.credit AS NVARCHAR(20))
                              FROM dbo.journalEntries e JOIN dbo.journalEntryLines l ON l.journalEntryId=e.entryId
                              JOIN dbo.chartOfAccounts a ON a.accountId=l.accountId
                              WHERE e.companyId=@A AND e.referenceType='income_commission' AND e.referenceId=@i1
                              ORDER BY l.debit DESC FOR XML PATH('')), 1, 1, '')), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'R2 no commission entry for I3/I4/I5/I7', '0',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries e JOIN @sales s2 ON s2.incomeId=e.referenceId
              WHERE e.companyId=@A AND e.referenceType='income_commission' AND s2.tag IN ('I3','I4','I5','I7')) AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'R2 I2 still has exactly one commission entry', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries e JOIN @sales s2 ON s2.incomeId=e.referenceId
              WHERE e.companyId=@A AND e.referenceType='income_commission' AND s2.tag='I2') AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'R2 company B untouched by A-only run', '0',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@B AND referenceType='income_commission') AS NVARCHAR(5));

    -- ── R3 re-run, company A → idempotent ────────────────────────────────────
    DELETE FROM @out;
    INSERT INTO @out EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = @A, @fromDate = '2026-09-01', @dryRun = 0;
    INSERT INTO @run SELECT 'R3', * FROM @out;
    INSERT INTO @checks (name, expected, actual) SELECT N'R3 re-run posts nothing (candidates/posted)', '0/0',
        (SELECT CAST(candidates AS NVARCHAR(5)) + '/' + CAST(posted AS NVARCHAR(5)) FROM @run WHERE label='R3');

    -- ── R4 company B (never all-companies here: that would touch real companies)
    DELETE FROM @out;
    INSERT INTO @out EXEC dbo.sp_journalEntries_backfillIncomeCommissions @companyId = @B, @fromDate = '2026-09-01', @dryRun = 0;
    INSERT INTO @run SELECT 'R4', * FROM @out;
    INSERT INTO @checks (name, expected, actual) SELECT N'R4 company B posted / amount', '1/2.10',
        (SELECT CAST(posted AS NVARCHAR(5)) + '/' + CAST(postedAmount AS NVARCHAR(20)) FROM @run WHERE label='R4');
    INSERT INTO @checks (name, expected, actual) SELECT N'R4 B entry references I6', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@B AND referenceType='income_commission' AND referenceId=@i6 AND status='POSTED') AS NVARCHAR(5));

    -- ── Ledger effect (via the shared aggregation) ───────────────────────────
    -- A Bancos at 2026-09-30: card sales I1+I2+I3 debit 300; commissions I1+I2 credit 8.40
    INSERT INTO @checks (name, expected, actual) SELECT N'A 1105 Bancos balance (300 - 8.40)', '291.60',
        ISNULL((SELECT CAST(balance AS NVARCHAR(30)) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30') WHERE code='1105'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'A 5120 Comisiones bancarias balance', '8.40',
        ISNULL((SELECT CAST(balance AS NVARCHAR(30)) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30') WHERE code='5120'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'A and B: every entry balances', '0',
        CAST((SELECT COUNT(*) FROM (SELECT e.entryId FROM dbo.journalEntries e JOIN dbo.journalEntryLines l ON l.journalEntryId=e.entryId
              WHERE e.companyId IN (@A,@B) GROUP BY e.entryId HAVING SUM(l.debit) <> SUM(l.credit)) x) AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'A and B: entryNumber unique per company', '0',
        CAST((SELECT COUNT(*) FROM (SELECT companyId, entryNumber FROM dbo.journalEntries WHERE companyId IN (@A,@B)
              GROUP BY companyId, entryNumber HAVING COUNT(*) > 1) x) AS NVARCHAR(5));
END TRY
BEGIN CATCH
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @checks (name, expected, actual) VALUES (N'TEST ERROR: ' + @err, 'no error', 'error');
END CATCH

IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

Report:
SELECT seq, CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 'PASS' ELSE 'FAIL' END AS result,
       name, expected, actual
FROM @checks ORDER BY seq;

SELECT CASE WHEN SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) = 0
            THEN 'STEP 4 GATE (SQL): ALL ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS PASS'
            ELSE 'STEP 4 GATE (SQL): ' + CAST(SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) AS NVARCHAR(10))
                 + ' OF ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS FAIL' END AS summary,
       (SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId IN (-9301, -9302))
     + (SELECT COUNT(*) FROM dbo.journalEntries  WHERE companyId IN (-9301, -9302))
     + (SELECT COUNT(*) FROM dbo.income          WHERE companyId IN (-9301, -9302)) AS leftoverTestRows
FROM @checks;
