-- =============================================================================
-- TEST — Step 7: reconcile movements vs journal + backfill missing postings
-- Roadmap Step 7 gate (POSVending/docs/accounting-module.md §7.5)
-- =============================================================================
-- SAFE TO RUN ON PRODUCTION: one transaction, ALWAYS rolled back (both SPs are
-- read-only or savepoint-aware). Fake companies -9601 (A) / -9602 (B); their
-- income, expenses, employee, accounts and entries vanish on rollback. The
-- all-companies reconcile run is read-only and is filtered to A/B here.
--
-- Company A (Hermosillo dates; paymentDate 18:00Z = 11:00 local same day):
--   M1 cash sale 09-10  $100, no entry                → MISSING_JOURNAL → backfill Dr 1101 / Cr 4105
--   M2 card sale 09-11  $200 (+8.40 commission), none → MISSING_JOURNAL → backfill Dr 1105 / Cr 4105
--   M3 card sale 09-12  $50, entry 50 on 09-12       → clean
--   M4 sale      09-13  $70, entry says 60           → AMOUNT_MISMATCH
--   M5 sale 09-14 19:00 local (09-15 02:00Z), entry dated 09-15 → DATE_MISMATCH
--   M6 sale      08-20  $999, no entry (before books) → ignored, never posted
--   M7 sale      09-16  $40, only a VOID entry        → VOID_MISMATCH (not re-posted)
--   M8 sale      09-18  $10, two POSTED entries       → DUPLICATE_JOURNAL
--   O1 POSTED income entry for a sale that doesn't exist → ORPHAN_JOURNAL
--   C1 company B's sale 09-21 $15 posted under company A → COMPANY_MISMATCH
--   E1 general expense Efectivo 09-19 $25, no entry  → backfill Dr 5115 / Cr 1101
--   E2 payroll Transferencia   09-20 $300, no entry  → backfill Dr 5110 / Cr 1105
-- Company B:
--   B1 sale 09-10 $80, no entry → MISSING_JOURNAL, untouched by an A-only backfill
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @A INT = -9601, @B INT = -9602;
DECLARE @checks TABLE (seq INT IDENTITY, name NVARCHAR(200), expected NVARCHAR(80), actual NVARCHAR(80));
DECLARE @rec TABLE (issueType NVARCHAR(30), companyId INT, referenceType NVARCHAR(30), referenceId INT,
                    movementAmount DECIMAL(12,2), journalAmount DECIMAL(12,2), movementDate DATE, journalDate DATE);
DECLARE @bf TABLE (dryRun BIT, incomeCandidates INT, expenseCandidates INT, posted INT, postedAmount DECIMAL(14,2), skippedMissingAccount INT);

INSERT INTO @checks (name, expected, actual)
SELECT N'reconcile + backfill SPs deployed', '1/1',
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_reconcileMovements', 'P') IS NOT NULL THEN '1' ELSE '0' END + '/' +
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_backfillMovements', 'P') IS NOT NULL THEN '1' ELSE '0' END;
IF OBJECT_ID('dbo.sp_journalEntries_reconcileMovements', 'P') IS NULL
   OR OBJECT_ID('dbo.sp_journalEntries_backfillMovements', 'P') IS NULL GOTO Report;

BEGIN TRANSACTION;
BEGIN TRY
    IF EXISTS (SELECT 1 FROM dbo.chartOfAccounts WHERE companyId IN (@A, @B))
        RAISERROR('Test companies -9601/-9602 already have accounts — aborting.', 16, 1);
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @A;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @B;

    -- Payroll needs a real employee (FK). companyId NULL: a fake company can't satisfy its FK.
    INSERT INTO dbo.employees (firstName, lastName, email, employmentTypeId, departmentId, statusId, createdAt)
    VALUES (N'Test', N'Step7', N'test.step7.' + CAST(NEWID() AS NVARCHAR(36)) + N'@example.invalid', 1, 1, 1, GETDATE());
    DECLARE @emp INT = SCOPE_IDENTITY();

    DECLARE @inc TABLE (tag NVARCHAR(5), companyId INT, method NVARCHAR(20), paidUtc DATETIME, total DECIMAL(10,2),
                        commission DECIMAL(10,2) NULL, incomeId INT NULL);
    INSERT INTO @inc (tag, companyId, method, paidUtc, total, commission) VALUES
        ('M1', @A, 'Efectivo', '2026-09-10T18:00:00', 100, NULL),
        ('M2', @A, 'Tarjeta',  '2026-09-11T18:00:00', 200, 8.40),
        ('M3', @A, 'Tarjeta',  '2026-09-12T18:00:00',  50, NULL),
        ('M4', @A, 'Efectivo', '2026-09-13T18:00:00',  70, NULL),
        ('M5', @A, 'Efectivo', '2026-09-15T02:00:00',  30, NULL),
        ('M6', @A, 'Efectivo', '2026-08-20T18:00:00', 999, NULL),
        ('M7', @A, 'Efectivo', '2026-09-16T18:00:00',  40, NULL),
        ('M8', @A, 'Efectivo', '2026-09-18T18:00:00',  10, NULL),
        ('C1', @B, 'Efectivo', '2026-09-21T18:00:00',  15, NULL),
        ('B1', @B, 'Efectivo', '2026-09-10T18:00:00',  80, NULL);

    DECLARE @tag NVARCHAR(5), @cid INT, @m NVARCHAR(20), @paid DATETIME, @tot DECIMAL(10,2), @com DECIMAL(10,2), @id INT;
    DECLARE ic CURSOR LOCAL FAST_FORWARD FOR SELECT tag, companyId, method, paidUtc, total, commission FROM @inc;
    OPEN ic; FETCH NEXT FROM ic INTO @tag, @cid, @m, @paid, @tot, @com;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO dbo.income (total, paymentMethod, paymentDate, userId, clientId, companyId, commissionRatePct, commissionAmount)
        VALUES (@tot, @m, @paid, 0, 0, @cid, CASE WHEN @com IS NULL THEN NULL ELSE 4.2 END, @com);
        SET @id = SCOPE_IDENTITY();
        UPDATE @inc SET incomeId = @id WHERE tag = @tag;
        FETCH NEXT FROM ic INTO @tag, @cid, @m, @paid, @tot, @com;
    END
    CLOSE ic; DEALLOCATE ic;

    INSERT INTO dbo.expenses (total, paymentMethod, paymentDate, userId, supplierId, companyId, expenseType, employeeId)
    VALUES (25, 'Efectivo', '2026-09-19T18:00:00', 0, -1, @A, 'general', NULL);
    DECLARE @E1 INT = SCOPE_IDENTITY();
    INSERT INTO dbo.expenses (total, paymentMethod, paymentDate, userId, supplierId, companyId, expenseType, employeeId)
    VALUES (300, 'Transferencia', '2026-09-20T18:00:00', 0, NULL, @A, 'payroll', @emp);
    DECLARE @E2 INT = SCOPE_IDENTITY();

    -- Pre-existing journal entries (company, refType, refId, status, date, amount, dr, cr)
    DECLARE @orphan INT = (SELECT ISNULL(MAX(incomeId), 0) + 1000000 FROM dbo.income);
    DECLARE @pre TABLE (companyId INT, refType NVARCHAR(30), refId INT, status NVARCHAR(10), entryDate DATE, amount DECIMAL(12,2), dr NVARCHAR(10), cr NVARCHAR(10));
    INSERT INTO @pre
    SELECT @A, 'income', incomeId, 'POSTED', '2026-09-12', 50, '1105', '4105' FROM @inc WHERE tag='M3' UNION ALL
    SELECT @A, 'income', incomeId, 'POSTED', '2026-09-13', 60, '1101', '4105' FROM @inc WHERE tag='M4' UNION ALL
    SELECT @A, 'income', incomeId, 'POSTED', '2026-09-15', 30, '1101', '4105' FROM @inc WHERE tag='M5' UNION ALL
    SELECT @A, 'income', incomeId, 'VOID',   '2026-09-16', 40, '1101', '4105' FROM @inc WHERE tag='M7' UNION ALL
    SELECT @A, 'income', incomeId, 'POSTED', '2026-09-18', 10, '1101', '4105' FROM @inc WHERE tag='M8' UNION ALL
    SELECT @A, 'income', incomeId, 'POSTED', '2026-09-18', 10, '1101', '4105' FROM @inc WHERE tag='M8' UNION ALL
    SELECT @A, 'income', incomeId, 'POSTED', '2026-09-21', 15, '1101', '4105' FROM @inc WHERE tag='C1' UNION ALL
    SELECT @A, 'income', @orphan,  'POSTED', '2026-09-17', 20, '1101', '4105';

    DECLARE @rt NVARCHAR(30), @rid INT, @st NVARCHAR(10), @ed DATE, @amt DECIMAL(12,2), @dr NVARCHAR(10), @cr NVARCHAR(10), @num INT, @eid INT;
    DECLARE pc CURSOR LOCAL FAST_FORWARD FOR SELECT companyId, refType, refId, status, entryDate, amount, dr, cr FROM @pre;
    OPEN pc; FETCH NEXT FROM pc INTO @cid, @rt, @rid, @st, @ed, @amt, @dr, @cr;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @num = ISNULL(MAX(entryNumber), 0) + 1 FROM dbo.journalEntries WHERE companyId = @cid;
        INSERT INTO dbo.journalEntries (companyId, entryNumber, entryDate, description, referenceType, referenceId, status, totalDebit, totalCredit)
        VALUES (@cid, @num, @ed, N'TEST pre', @rt, @rid, @st, @amt, @amt);
        SET @eid = SCOPE_IDENTITY();
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
        SELECT @eid, accountId, @amt, 0 FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = @dr;
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
        SELECT @eid, accountId, 0, @amt FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = @cr;
        FETCH NEXT FROM pc INTO @cid, @rt, @rid, @st, @ed, @amt, @dr, @cr;
    END
    CLOSE pc; DEALLOCATE pc;

    -- ── Reconcile (all companies, read-only) → keep A/B rows ─────────────────
    INSERT INTO @rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = NULL, @fromDate = '2026-09-01';
    DELETE FROM @rec WHERE companyId NOT IN (@A, @B);

    INSERT INTO @checks (name, expected, actual) SELECT N'R0 A MISSING_JOURNAL (M1, M2, E1, E2)', '4',
        CAST((SELECT COUNT(*) FROM @rec WHERE companyId=@A AND issueType='MISSING_JOURNAL') AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'R0 A AMOUNT_MISMATCH M4 (70 vs 60)', '70.00/60.00',
        ISNULL((SELECT CAST(movementAmount AS NVARCHAR(20)) + '/' + CAST(journalAmount AS NVARCHAR(20)) FROM @rec WHERE companyId=@A AND issueType='AMOUNT_MISMATCH'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'R0 A DATE_MISMATCH M5 (09-14 vs 09-15)', '2026-09-14/2026-09-15',
        ISNULL((SELECT CONVERT(NVARCHAR(10), movementDate, 23) + '/' + CONVERT(NVARCHAR(10), journalDate, 23) FROM @rec WHERE companyId=@A AND issueType='DATE_MISMATCH'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'R0 A VOID_MISMATCH / DUPLICATE / ORPHAN / COMPANY_MISMATCH', '1/1/1/1',
        CAST((SELECT COUNT(*) FROM @rec WHERE companyId=@A AND issueType='VOID_MISMATCH') AS NVARCHAR(5)) + '/' +
        CAST((SELECT COUNT(*) FROM @rec WHERE companyId=@A AND issueType='DUPLICATE_JOURNAL') AS NVARCHAR(5)) + '/' +
        CAST((SELECT COUNT(*) FROM @rec WHERE companyId=@A AND issueType='ORPHAN_JOURNAL' AND referenceId=@orphan) AS NVARCHAR(5)) + '/' +
        CAST((SELECT COUNT(*) FROM @rec WHERE companyId=@A AND issueType='COMPANY_MISMATCH') AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'R0 M6 (before books) never reported', '0',
        CAST((SELECT COUNT(*) FROM @rec r JOIN @inc i ON i.incomeId = r.referenceId AND r.referenceType = 'income' WHERE i.tag='M6') AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'R0 M3 (clean) never reported', '0',
        CAST((SELECT COUNT(*) FROM @rec r JOIN @inc i ON i.incomeId = r.referenceId AND r.referenceType = 'income' WHERE i.tag='M3') AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'R0 B MISSING_JOURNAL (B1)', '1',
        CAST((SELECT COUNT(*) FROM @rec WHERE companyId=@B AND issueType='MISSING_JOURNAL') AS NVARCHAR(5));

    -- ── Backfill A: dry run, real run, re-run ────────────────────────────────
    DECLARE @jeA0 INT = (SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A);
    INSERT INTO @bf EXEC dbo.sp_journalEntries_backfillMovements @companyId = @A, @fromDate = '2026-09-01', @dryRun = 1;
    INSERT INTO @checks (name, expected, actual) SELECT N'B1 dry run: income/expense candidates, posted', '2/2/0',
        (SELECT TOP 1 CAST(incomeCandidates AS NVARCHAR(5)) + '/' + CAST(expenseCandidates AS NVARCHAR(5)) + '/' + CAST(posted AS NVARCHAR(5)) FROM @bf);
    INSERT INTO @checks (name, expected, actual) SELECT N'B1 dry run wrote nothing', CAST(@jeA0 AS NVARCHAR(10)),
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A) AS NVARCHAR(10));

    DELETE FROM @bf;
    INSERT INTO @bf EXEC dbo.sp_journalEntries_backfillMovements @companyId = @A, @fromDate = '2026-09-01', @dryRun = 0;
    INSERT INTO @checks (name, expected, actual) SELECT N'B2 posted / amount (100+200+25+300)', '4/625.00',
        (SELECT TOP 1 CAST(posted AS NVARCHAR(5)) + '/' + CAST(postedAmount AS NVARCHAR(20)) FROM @bf);

    DECLARE @mapCheck NVARCHAR(400) = (
        SELECT STUFF((
            SELECT '|' + e.referenceType + ':' + CONVERT(NVARCHAR(10), e.entryDate, 23) + ':'
                 + (SELECT a.code FROM dbo.journalEntryLines l JOIN dbo.chartOfAccounts a ON a.accountId=l.accountId WHERE l.journalEntryId=e.entryId AND l.debit>0) + '>'
                 + (SELECT a.code FROM dbo.journalEntryLines l JOIN dbo.chartOfAccounts a ON a.accountId=l.accountId WHERE l.journalEntryId=e.entryId AND l.credit>0)
            FROM dbo.journalEntries e
            WHERE e.companyId=@A AND e.description LIKE N'%(backfill)'
            ORDER BY e.entryDate
            FOR XML PATH('')), 1, 1, ''));
    INSERT INTO @checks (name, expected, actual) SELECT N'B2 map + dates (Dr>Cr)',
        'income:2026-09-10:1101>4105|income:2026-09-11:1105>4105|expense:2026-09-19:5115>1101|expense:2026-09-20:5110>1105',
        ISNULL(@mapCheck, '(none)');

    DELETE FROM @bf;
    INSERT INTO @bf EXEC dbo.sp_journalEntries_backfillMovements @companyId = @A, @fromDate = '2026-09-01', @dryRun = 0;
    INSERT INTO @checks (name, expected, actual) SELECT N'B3 re-run posts nothing', '0/0/0',
        (SELECT TOP 1 CAST(incomeCandidates AS NVARCHAR(5)) + '/' + CAST(expenseCandidates AS NVARCHAR(5)) + '/' + CAST(posted AS NVARCHAR(5)) FROM @bf);

    -- ── After: reconcile A again ─────────────────────────────────────────────
    DELETE FROM @rec;
    INSERT INTO @rec EXEC dbo.sp_journalEntries_reconcileMovements @companyId = @A, @fromDate = '2026-09-01';
    INSERT INTO @checks (name, expected, actual) SELECT N'A1 A MISSING_JOURNAL after backfill', '0',
        CAST((SELECT COUNT(*) FROM @rec WHERE issueType='MISSING_JOURNAL') AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'A1 M2 now shows MISSING_COMMISSION (8.40)', '8.40',
        ISNULL((SELECT CAST(movementAmount AS NVARCHAR(20)) FROM @rec WHERE issueType='MISSING_COMMISSION'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'A1 VOID_MISMATCH M7 was not re-posted', '1',
        CAST((SELECT COUNT(*) FROM @rec WHERE issueType='VOID_MISMATCH') AS NVARCHAR(5));

    -- ── Isolation + integrity ────────────────────────────────────────────────
    INSERT INTO @checks (name, expected, actual) SELECT N'B untouched by A-only backfill (B entries)', '0',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@B) AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'every A entry balances; folios unique', '0/0',
        CAST((SELECT COUNT(*) FROM (SELECT e.entryId FROM dbo.journalEntries e JOIN dbo.journalEntryLines l ON l.journalEntryId=e.entryId
              WHERE e.companyId=@A GROUP BY e.entryId HAVING SUM(l.debit) <> SUM(l.credit)) x) AS NVARCHAR(5)) + '/' +
        CAST((SELECT COUNT(*) FROM (SELECT entryNumber FROM dbo.journalEntries WHERE companyId=@A GROUP BY entryNumber HAVING COUNT(*) > 1) x) AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'M6 (before books) never posted', '0',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries e JOIN @inc i ON i.incomeId=e.referenceId AND e.referenceType='income' WHERE i.tag='M6') AS NVARCHAR(5));
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
            THEN 'STEP 7 GATE (SQL): ALL ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS PASS'
            ELSE 'STEP 7 GATE (SQL): ' + CAST(SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) AS NVARCHAR(10))
                 + ' OF ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS FAIL' END AS summary,
       (SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId IN (-9601, -9602))
     + (SELECT COUNT(*) FROM dbo.journalEntries  WHERE companyId IN (-9601, -9602))
     + (SELECT COUNT(*) FROM dbo.income          WHERE companyId IN (-9601, -9602))
     + (SELECT COUNT(*) FROM dbo.expenses        WHERE companyId IN (-9601, -9602))
     + (SELECT COUNT(*) FROM dbo.employees       WHERE lastName = N'Step7' AND firstName = N'Test') AS leftoverTestRows
FROM @checks;
