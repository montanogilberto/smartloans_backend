-- =============================================================================
-- TEST — accounting aggregation: cutoff / VOID / company isolation
-- Roadmap Step 1 gate (POSVending/docs/accounting-module.md §7.6)
-- Object under test: dbo.fn_journalEntries_accountTotals (used by
-- sp_journalEntries_trialBalance and, later, Balance General / P&L).
-- =============================================================================
-- SAFE TO RUN ON PRODUCTION: everything happens inside one transaction that is
-- ALWAYS rolled back. Uses fake companies -9001 / -9002 (no real company has a
-- negative id), seeded with the standard catalog via sp_chartOfAccounts_seed.
-- Leaves no rows behind (identity values consumed by the rollback are harmless).
--
-- Why the function and not the SP: SQL Server rejects INSERT…EXEC of a
-- procedure that uses FOR JSON, so the SP's output can't be captured in T-SQL.
-- The SP is a thin JSON wrapper over this function (checked below by
-- definition); its JSON is verified through the live API after deploy.
--
-- HOW TO READ: the last result sets list every check with PASS/FAIL, one
-- summary row, and leftoverTestRows (must be 0).
--
-- Data (all amounts are Dr / Cr pairs):
--   Company A (-9001)
--     E1 POSTED 2026-09-15  Dr 1105  100   Cr 4105  100   -> in  (before cutoff)
--     E2 POSTED 2026-09-30  Dr 1105   50   Cr 4105   50   -> in  (on cutoff)
--     E3 POSTED 2026-10-01  Dr 1105    7   Cr 4105    7   -> out (after cutoff)
--     E4 VOID   2026-09-10  Dr 1105 1000   Cr 4105 1000   -> out (void)
--     E5 VOID   2026-10-05  Dr 5105    3   Cr 1105    3   -> out (void, after)
--   Company B (-9002)
--     E6 POSTED 2026-09-20  Dr 1105  999   Cr 4105  999   -> only in B
-- =============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @A INT = -9001, @B INT = -9002;

DECLARE @checks TABLE (seq INT IDENTITY, name NVARCHAR(200), expected NVARCHAR(50), actual NVARCHAR(50));
DECLARE @res TABLE (scenario NVARCHAR(10), code NVARCHAR(20), debitTotal DECIMAL(14,2), creditTotal DECIMAL(14,2), balance DECIMAL(14,2));

-- Deployment checks (outside the fixture transaction).
INSERT INTO @checks (name, expected, actual)
SELECT N'fn_journalEntries_accountTotals deployed', '1',
       CASE WHEN OBJECT_ID('dbo.fn_journalEntries_accountTotals', 'IF') IS NOT NULL THEN '1' ELSE '0' END;
INSERT INTO @checks (name, expected, actual)
SELECT N'sp_journalEntries_trialBalance uses the function', '1',
       CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries_trialBalance'))
                 LIKE '%fn_journalEntries_accountTotals%' THEN '1' ELSE '0' END;

IF OBJECT_ID('dbo.fn_journalEntries_accountTotals', 'IF') IS NULL
    GOTO Report;   -- nothing else can run without the function

BEGIN TRANSACTION;
BEGIN TRY
    -- ── Fixture ───────────────────────────────────────────────────────────────
    IF EXISTS (SELECT 1 FROM dbo.chartOfAccounts WHERE companyId IN (@A, @B))
        RAISERROR('Test companies -9001/-9002 already have accounts — aborting.', 16, 1);

    EXEC dbo.sp_chartOfAccounts_seed @companyId = @A;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @B;

    DECLARE @defs TABLE (tag NVARCHAR(5), companyId INT, entryDate DATE, status NVARCHAR(10),
                         drCode NVARCHAR(20), crCode NVARCHAR(20), amount DECIMAL(12,2));
    INSERT INTO @defs VALUES
        ('E1', @A, '2026-09-15', 'POSTED', '1105', '4105',  100),
        ('E2', @A, '2026-09-30', 'POSTED', '1105', '4105',   50),
        ('E3', @A, '2026-10-01', 'POSTED', '1105', '4105',    7),
        ('E4', @A, '2026-09-10', 'VOID',   '1105', '4105', 1000),
        ('E5', @A, '2026-10-05', 'VOID',   '5105', '1105',    3),
        ('E6', @B, '2026-09-20', 'POSTED', '1105', '4105',  999);

    DECLARE @tag NVARCHAR(5), @cid INT, @dt DATE, @st NVARCHAR(10), @dr NVARCHAR(20), @cr NVARCHAR(20),
            @amt DECIMAL(12,2), @num INT, @entryId INT;
    DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT tag, companyId, entryDate, status, drCode, crCode, amount FROM @defs;
    OPEN c;
    FETCH NEXT FROM c INTO @tag, @cid, @dt, @st, @dr, @cr, @amt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @num = ISNULL(MAX(entryNumber), 0) + 1 FROM dbo.journalEntries WHERE companyId = @cid;
        INSERT INTO dbo.journalEntries (companyId, entryNumber, entryDate, description, referenceType, status, totalDebit, totalCredit)
        VALUES (@cid, @num, @dt, N'TEST ' + @tag, 'manual', @st, @amt, @amt);
        SET @entryId = SCOPE_IDENTITY();
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit, lineDescription)
        SELECT @entryId, accountId, @amt, 0, N'TEST ' + @tag FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = @dr;
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit, lineDescription)
        SELECT @entryId, accountId, 0, @amt, N'TEST ' + @tag FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = @cr;
        FETCH NEXT FROM c INTO @tag, @cid, @dt, @st, @dr, @cr, @amt;
    END
    CLOSE c; DEALLOCATE c;

    -- ── Scenarios ────────────────────────────────────────────────────────────
    INSERT INTO @res SELECT 'S1', code, debitTotal, creditTotal, balance FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30'); -- normal cutoff
    INSERT INTO @res SELECT 'S2', code, debitTotal, creditTotal, balance FROM dbo.fn_journalEntries_accountTotals(@A, NULL);         -- no cutoff
    INSERT INTO @res SELECT 'S3', code, debitTotal, creditTotal, balance FROM dbo.fn_journalEntries_accountTotals(@B, '2026-09-30'); -- company B
    INSERT INTO @res SELECT 'S4', code, debitTotal, creditTotal, balance FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-14'); -- before A's POSTED

    DECLARE @n NVARCHAR(30) = N'(none)';
    -- S1: A at 2026-09-30 → E1 + E2 only
    INSERT INTO @checks (name, expected, actual) SELECT N'S1 POSTED before + on cutoff: 1105 debit', '150.00',
        ISNULL((SELECT CAST(debitTotal AS NVARCHAR(30)) FROM @res WHERE scenario='S1' AND code='1105'), @n);
    INSERT INTO @checks (name, expected, actual) SELECT N'S1 VOID credit excluded: 1105 credit', '0.00',
        ISNULL((SELECT CAST(creditTotal AS NVARCHAR(30)) FROM @res WHERE scenario='S1' AND code='1105'), @n);
    INSERT INTO @checks (name, expected, actual) SELECT N'S1 1105 balance (debit-normal)', '150.00',
        ISNULL((SELECT CAST(balance AS NVARCHAR(30)) FROM @res WHERE scenario='S1' AND code='1105'), @n);
    INSERT INTO @checks (name, expected, actual) SELECT N'S1 4105 credit (after-cutoff + VOID excluded)', '150.00',
        ISNULL((SELECT CAST(creditTotal AS NVARCHAR(30)) FROM @res WHERE scenario='S1' AND code='4105'), @n);
    INSERT INTO @checks (name, expected, actual) SELECT N'S1 4105 balance (credit-normal)', '150.00',
        ISNULL((SELECT CAST(balance AS NVARCHAR(30)) FROM @res WHERE scenario='S1' AND code='4105'), @n);
    INSERT INTO @checks (name, expected, actual) SELECT N'S1 VOID-only account 5105 absent', @n,
        ISNULL((SELECT CAST(debitTotal AS NVARCHAR(30)) FROM @res WHERE scenario='S1' AND code='5105'), @n);
    INSERT INTO @checks (name, expected, actual) SELECT N'S1 account rows', '2',
        CAST((SELECT COUNT(*) FROM @res WHERE scenario='S1') AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'S1 debits = credits (balanced)', '150.00/150.00',
        (SELECT CAST(SUM(debitTotal) AS NVARCHAR(20)) + '/' + CAST(SUM(creditTotal) AS NVARCHAR(20)) FROM @res WHERE scenario='S1');

    -- S2: A, no cutoff → E1 + E2 + E3, still no VOID
    INSERT INTO @checks (name, expected, actual) SELECT N'S2 no cutoff: 1105 debit (E1+E2+E3)', '157.00',
        ISNULL((SELECT CAST(debitTotal AS NVARCHAR(30)) FROM @res WHERE scenario='S2' AND code='1105'), @n);
    INSERT INTO @checks (name, expected, actual) SELECT N'S2 no cutoff: VOID-only 5105 absent', @n,
        ISNULL((SELECT CAST(debitTotal AS NVARCHAR(30)) FROM @res WHERE scenario='S2' AND code='5105'), @n);
    INSERT INTO @checks (name, expected, actual) SELECT N'S2 debits = credits (balanced)', '157.00/157.00',
        (SELECT CAST(SUM(debitTotal) AS NVARCHAR(20)) + '/' + CAST(SUM(creditTotal) AS NVARCHAR(20)) FROM @res WHERE scenario='S2');

    -- S3: company isolation
    INSERT INTO @checks (name, expected, actual) SELECT N'S3 company B sees only its own 1105', '999.00',
        ISNULL((SELECT CAST(debitTotal AS NVARCHAR(30)) FROM @res WHERE scenario='S3' AND code='1105'), @n);
    INSERT INTO @checks (name, expected, actual) SELECT N'S3 company B debits = credits', '999.00/999.00',
        (SELECT CAST(SUM(debitTotal) AS NVARCHAR(20)) + '/' + CAST(SUM(creditTotal) AS NVARCHAR(20)) FROM @res WHERE scenario='S3');
    INSERT INTO @checks (name, expected, actual) SELECT N'S1/S2 company A has none of B''s 999', '0',
        CAST((SELECT COUNT(*) FROM @res WHERE scenario IN ('S1','S2') AND (debitTotal >= 999 OR creditTotal >= 999)) AS NVARCHAR(10));

    -- S4: cutoff before every POSTED entry of A (E4 VOID on 09-10 must not count)
    INSERT INTO @checks (name, expected, actual) SELECT N'S4 early cutoff: account rows (VOID 09-10 ignored)', '0',
        CAST((SELECT COUNT(*) FROM @res WHERE scenario='S4') AS NVARCHAR(10));
END TRY
BEGIN CATCH
    -- A doomed transaction can't take writes (not even to a table variable):
    -- roll back first, then record the error.
    DECLARE @err NVARCHAR(4000) = ERROR_MESSAGE();
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @checks (name, expected, actual) VALUES (N'TEST ERROR: ' + @err, 'no error', 'error');
END CATCH

-- Always undo the fixture.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

Report:
SELECT seq, CASE WHEN ISNULL(expected, '') = ISNULL(actual, '') THEN 'PASS' ELSE 'FAIL' END AS result,
       name, expected, actual
FROM @checks ORDER BY seq;

SELECT CASE WHEN SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) = 0
            THEN 'STEP 1 GATE: ALL ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS PASS'
            ELSE 'STEP 1 GATE: ' + CAST(SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) AS NVARCHAR(10))
                 + ' OF ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS FAIL' END AS summary
FROM @checks;

-- Proof nothing was left behind (expect 0).
SELECT COUNT(*) AS leftoverTestRows FROM dbo.chartOfAccounts WHERE companyId IN (-9001, -9002);
