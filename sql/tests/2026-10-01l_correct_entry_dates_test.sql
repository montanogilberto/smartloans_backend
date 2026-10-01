-- =============================================================================
-- TEST — Step 7: sp_journalEntries_correctDates (VOID + re-post on the right day)
-- =============================================================================
-- SAFE TO RUN ON PRODUCTION: one transaction, ALWAYS rolled back. Fake
-- companies -9801 (A), -9802 (B).
--   S1 card sale Sept 30 19:31 Hermosillo (2026-10-01 02:31Z) $420, entry dated 10-01,
--      commission $17.64 dated 10-01                         → both corrected to 09-30
--   S2 cash sale 09-15, entry 09-15                          → untouched
--   S3 sale 09-15 evening, only a VOID entry dated 09-16     → untouched (not POSTED)
--   E1 expense 09-20 noon Hermosillo, entry dated 09-21      → corrected to 09-20
--   B1 company B sale like S1, entry dated 10-01             → untouched by an A-only run
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @A INT = -9801, @B INT = -9802;
DECLARE @checks TABLE (seq INT IDENTITY, name NVARCHAR(200), expected NVARCHAR(120), actual NVARCHAR(120));
DECLARE @out TABLE (dryRun BIT, candidates INT, corrected INT, amount DECIMAL(14,2));

INSERT INTO @checks (name, expected, actual)
SELECT N'sp_journalEntries_correctDates deployed', '1',
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_correctDates', 'P') IS NOT NULL THEN '1' ELSE '0' END;
IF OBJECT_ID('dbo.sp_journalEntries_correctDates', 'P') IS NULL GOTO Report;

BEGIN TRANSACTION;
BEGIN TRY
    IF EXISTS (SELECT 1 FROM dbo.chartOfAccounts WHERE companyId IN (@A, @B))
        RAISERROR('Test companies -9801/-9802 already have accounts — aborting.', 16, 1);
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @A;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @B;

    INSERT INTO dbo.income (total, paymentMethod, paymentDate, userId, clientId, companyId, commissionRatePct, commissionAmount)
    VALUES (420, 'Tarjeta', '2026-10-01T02:31:00', 0, 0, @A, 4.2, 17.64);
    DECLARE @S1 INT = SCOPE_IDENTITY();
    INSERT INTO dbo.income (total, paymentMethod, paymentDate, userId, clientId, companyId) VALUES (100, 'Efectivo', '2026-09-15T18:00:00', 0, 0, @A);
    DECLARE @S2 INT = SCOPE_IDENTITY();
    INSERT INTO dbo.income (total, paymentMethod, paymentDate, userId, clientId, companyId) VALUES (30, 'Efectivo', '2026-09-16T03:00:00', 0, 0, @A);
    DECLARE @S3 INT = SCOPE_IDENTITY();
    INSERT INTO dbo.income (total, paymentMethod, paymentDate, userId, clientId, companyId) VALUES (90, 'Efectivo', '2026-10-01T02:00:00', 0, 0, @B);
    DECLARE @B1 INT = SCOPE_IDENTITY();
    INSERT INTO dbo.expenses (total, paymentMethod, paymentDate, userId, supplierId, companyId, expenseType)
    VALUES (50, 'Efectivo', '2026-09-20T19:00:00', 0, -1, @A, 'general');
    DECLARE @E1 INT = SCOPE_IDENTITY();

    DECLARE @j TABLE (companyId INT, refType NVARCHAR(30), refId INT, status NVARCHAR(10), entryDate DATE, dr NVARCHAR(10), cr NVARCHAR(10), amt DECIMAL(12,2));
    INSERT INTO @j VALUES
        (@A, 'income',            @S1, 'POSTED', '2026-10-01', '1105', '4105', 420),
        (@A, 'income_commission', @S1, 'POSTED', '2026-10-01', '5120', '1105', 17.64),
        (@A, 'income',            @S2, 'POSTED', '2026-09-15', '1101', '4105', 100),
        (@A, 'income',            @S3, 'VOID',   '2026-09-16', '1101', '4105', 30),
        (@A, 'expense',           @E1, 'POSTED', '2026-09-21', '5115', '1101', 50),
        (@B, 'income',            @B1, 'POSTED', '2026-10-01', '1101', '4105', 90);
    DECLARE @cid INT, @rt NVARCHAR(30), @rid INT, @st NVARCHAR(10), @ed DATE, @dr NVARCHAR(10), @cr NVARCHAR(10), @amt DECIMAL(12,2), @num INT, @eid INT;
    DECLARE jc CURSOR LOCAL FAST_FORWARD FOR SELECT companyId, refType, refId, status, entryDate, dr, cr, amt FROM @j;
    OPEN jc; FETCH NEXT FROM jc INTO @cid, @rt, @rid, @st, @ed, @dr, @cr, @amt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @num = ISNULL(MAX(entryNumber), 0) + 1 FROM dbo.journalEntries WHERE companyId = @cid;
        INSERT INTO dbo.journalEntries (companyId, entryNumber, entryDate, description, referenceType, referenceId, status, totalDebit, totalCredit)
        VALUES (@cid, @num, @ed, N'TEST ' + @rt, @rt, @rid, @st, @amt, @amt);
        SET @eid = SCOPE_IDENTITY();
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit, lineDescription)
        SELECT @eid, accountId, @amt, 0, N'dr' FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = @dr;
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit, lineDescription)
        SELECT @eid, accountId, 0, @amt, N'cr' FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = @cr;
        FETCH NEXT FROM jc INTO @cid, @rt, @rid, @st, @ed, @dr, @cr, @amt;
    END
    CLOSE jc; DEALLOCATE jc;

    DECLARE @postedA0 INT = (SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND status='POSTED');
    DECLARE @s2Entry INT = (SELECT entryId FROM dbo.journalEntries WHERE companyId=@A AND referenceId=@S2 AND referenceType='income');

    -- Dry run
    INSERT INTO @out EXEC dbo.sp_journalEntries_correctDates @companyId = @A, @fromDate = '2026-09-01', @dryRun = 1;
    INSERT INTO @checks (name, expected, actual) SELECT N'dry run: candidates/corrected/amount', '3/0/487.64',
        (SELECT TOP 1 CAST(candidates AS NVARCHAR(5)) + '/' + CAST(corrected AS NVARCHAR(5)) + '/' + CAST(amount AS NVARCHAR(20)) FROM @out);
    INSERT INTO @checks (name, expected, actual) SELECT N'dry run changed nothing (A POSTED count)', CAST(@postedA0 AS NVARCHAR(5)),
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND status='POSTED') AS NVARCHAR(5));

    -- Real run
    DELETE FROM @out;
    INSERT INTO @out EXEC dbo.sp_journalEntries_correctDates @companyId = @A, @fromDate = '2026-09-01', @dryRun = 0;
    INSERT INTO @checks (name, expected, actual) SELECT N'real run: corrected/amount', '3/487.64',
        (SELECT TOP 1 CAST(corrected AS NVARCHAR(5)) + '/' + CAST(amount AS NVARCHAR(20)) FROM @out);
    INSERT INTO @checks (name, expected, actual) SELECT N'originals now VOID (S1 income, S1 commission, E1)', '3',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND status='VOID'
              AND ((referenceId=@S1 AND referenceType IN ('income','income_commission')) OR (referenceId=@E1 AND referenceType='expense'))) AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'new POSTED dates (S1 inc / S1 com / E1)', '2026-09-30/2026-09-30/2026-09-20',
        ISNULL((SELECT CONVERT(NVARCHAR(10), entryDate, 23) FROM dbo.journalEntries WHERE companyId=@A AND status='POSTED' AND referenceType='income' AND referenceId=@S1), '(none)') + '/' +
        ISNULL((SELECT CONVERT(NVARCHAR(10), entryDate, 23) FROM dbo.journalEntries WHERE companyId=@A AND status='POSTED' AND referenceType='income_commission' AND referenceId=@S1), '(none)') + '/' +
        ISNULL((SELECT CONVERT(NVARCHAR(10), entryDate, 23) FROM dbo.journalEntries WHERE companyId=@A AND status='POSTED' AND referenceType='expense' AND referenceId=@E1), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'new entries marked "(fecha corregida)"', '3',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND status='POSTED' AND description LIKE N'%(fecha corregida)') AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'S1 new lines identical: Dr 1105 420 / Cr 4105 420', '1105:420.00:0.00|4105:0.00:420.00',
        ISNULL((SELECT STUFF((SELECT '|' + a.code + ':' + CAST(l.debit AS NVARCHAR(20)) + ':' + CAST(l.credit AS NVARCHAR(20))
                              FROM dbo.journalEntries e JOIN dbo.journalEntryLines l ON l.journalEntryId=e.entryId
                              JOIN dbo.chartOfAccounts a ON a.accountId=l.accountId
                              WHERE e.companyId=@A AND e.status='POSTED' AND e.referenceType='income' AND e.referenceId=@S1
                              ORDER BY l.debit DESC FOR XML PATH('')), 1, 1, '')), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'still one POSTED per reference (S1 inc/com, E1)', '1/1/1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND status='POSTED' AND referenceType='income' AND referenceId=@S1) AS NVARCHAR(3)) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND status='POSTED' AND referenceType='income_commission' AND referenceId=@S1) AS NVARCHAR(3)) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND status='POSTED' AND referenceType='expense' AND referenceId=@E1) AS NVARCHAR(3));
    INSERT INTO @checks (name, expected, actual) SELECT N'Sept 30 cutoff now includes S1: Bancos / Ventas', '402.36/520.00',
        ISNULL((SELECT CAST(balance AS NVARCHAR(20)) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30') WHERE code='1105'), '(none)') + '/' +
        ISNULL((SELECT CAST(balance AS NVARCHAR(20)) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30') WHERE code='4105'), '(none)');

    -- Untouched + idempotent + isolation
    INSERT INTO @checks (name, expected, actual) SELECT N'S2 (correct date) untouched', 'POSTED/1',
        (SELECT status FROM dbo.journalEntries WHERE entryId=@s2Entry) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income' AND referenceId=@S2) AS NVARCHAR(3));
    INSERT INTO @checks (name, expected, actual) SELECT N'S3 (VOID only) untouched', 'VOID/1',
        (SELECT TOP 1 status FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income' AND referenceId=@S3) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income' AND referenceId=@S3) AS NVARCHAR(3));
    DELETE FROM @out;
    INSERT INTO @out EXEC dbo.sp_journalEntries_correctDates @companyId = @A, @fromDate = '2026-09-01', @dryRun = 0;
    INSERT INTO @checks (name, expected, actual) SELECT N're-run finds nothing (candidates/corrected)', '0/0',
        (SELECT TOP 1 CAST(candidates AS NVARCHAR(5)) + '/' + CAST(corrected AS NVARCHAR(5)) FROM @out);
    INSERT INTO @checks (name, expected, actual) SELECT N'company B untouched (still dated 10-01, POSTED)', '2026-10-01/POSTED/1',
        (SELECT CONVERT(NVARCHAR(10), entryDate, 23) + '/' + status FROM dbo.journalEntries WHERE companyId=@B AND referenceId=@B1) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@B) AS NVARCHAR(3));
    INSERT INTO @checks (name, expected, actual) SELECT N'A: every entry balances; folios unique', '0/0',
        CAST((SELECT COUNT(*) FROM (SELECT e.entryId FROM dbo.journalEntries e JOIN dbo.journalEntryLines l ON l.journalEntryId=e.entryId
              WHERE e.companyId=@A GROUP BY e.entryId HAVING SUM(l.debit) <> SUM(l.credit)) x) AS NVARCHAR(5)) + '/' +
        CAST((SELECT COUNT(*) FROM (SELECT entryNumber FROM dbo.journalEntries WHERE companyId=@A GROUP BY entryNumber HAVING COUNT(*) > 1) x) AS NVARCHAR(5));
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
            THEN 'DATE CORRECTION GATE (SQL): ALL ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS PASS'
            ELSE 'DATE CORRECTION GATE (SQL): ' + CAST(SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) AS NVARCHAR(10))
                 + ' OF ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS FAIL' END AS summary,
       (SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId IN (-9801, -9802))
     + (SELECT COUNT(*) FROM dbo.journalEntries  WHERE companyId IN (-9801, -9802))
     + (SELECT COUNT(*) FROM dbo.income          WHERE companyId IN (-9801, -9802))
     + (SELECT COUNT(*) FROM dbo.expenses        WHERE companyId IN (-9801, -9802)) AS leftoverTestRows
FROM @checks;
