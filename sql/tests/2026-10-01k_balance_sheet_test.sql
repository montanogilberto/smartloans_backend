-- =============================================================================
-- TEST — Step 8: Balance General (fn_journalEntries_balanceSheet + JSON)
-- Roadmap Step 8 gate — the plan's ACCOUNTING ACCEPTANCE TEST MATRIX
-- =============================================================================
-- SAFE TO RUN ON PRODUCTION: one transaction, ALWAYS rolled back. Fake
-- companies -9701 (A), -9702 (B), -9703 (C, empty). The JSON is read from the
-- scalar function fn_journalEntries_balanceSheetJson (the SP only wraps it;
-- the SP's own JSON is checked through the API after deploy).
--
-- Company A journal (POSTED unless noted):
--   2025-12-15  Dr 1101 Caja 40          / Cr 4105 Ventas 40          (prior year)
--   2026-09-01  Dr 1101 Caja 1000        / Cr 3105 Capital 1000       (Test 1 opening)
--   2026-09-05  Dr 1101 Caja 100         / Cr 4105 Ventas 100         (Test 2 cash sale)
--   2026-09-06  Dr 1105 Bancos 100       / Cr 4105 Ventas 100         (Test 3 card sale)
--   2026-09-06  Dr 5120 Comisiones 4.20  / Cr 1105 Bancos 4.20        (Test 3 commission)
--   2026-09-07  Dr 5115 Servicios 50     / Cr 1101 Caja 50            (Test 4 cash expense)
--   2026-09-08  Dr 5105 Gastos 50        / Cr 1105 Bancos 50          (Test 5 bank expense)
--   2026-09-09  Dr 1101 999 / Cr 4105 999   VOID                      (Test 6)
--   2026-10-05  Dr 1101 7   / Cr 4105 7     after cutoff              (Test 7)
--   2026-09-10  Dr 1105 Bancos 300       / Cr 2105 CxP 300            (current liability)
--   2026-09-11  Dr 1105 Bancos 500       / Cr 2205 Préstamo LP 500    (non-current liability)
--   2026-09-12  Dr 1205 Equipo 200       / Cr 1105 Bancos 200         (non-current asset)
-- Expected at 2026-09-30:
--   Activo circulante:    Caja 1090.00, Bancos 645.80   → total activo 1935.80 (+ Equipo 200 no circ.)
--   Pasivo:               CxP 300 (corto), Préstamo LP 500 (largo) → 800.00
--   Capital:              Capital social 1000, anteriores 40.00, del ejercicio 95.80 → 1135.80
--   Pasivo + Capital = 1935.80 → balanced
-- Comparison at 2025-12-31: Caja 40 = resultado del ejercicio 40.
-- Company B: Dr 1101 5000 / Cr 3105 5000 (isolation). Company C: no entries.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @A INT = -9701, @B INT = -9702, @C INT = -9703;
DECLARE @checks TABLE (seq INT IDENTITY, name NVARCHAR(200), expected NVARCHAR(80), actual NVARCHAR(80));

INSERT INTO @checks (name, expected, actual)
SELECT N'balance sheet objects deployed (fn/json/sp)', '1/1/1',
       CASE WHEN OBJECT_ID('dbo.fn_journalEntries_balanceSheet', 'IF') IS NOT NULL THEN '1' ELSE '0' END + '/' +
       CASE WHEN OBJECT_ID('dbo.fn_journalEntries_balanceSheetJson', 'FN') IS NOT NULL THEN '1' ELSE '0' END + '/' +
       CASE WHEN OBJECT_ID('dbo.sp_journalEntries_balanceSheet', 'P') IS NOT NULL THEN '1' ELSE '0' END;
IF OBJECT_ID('dbo.fn_journalEntries_balanceSheetJson', 'FN') IS NULL GOTO Report;

BEGIN TRANSACTION;
BEGIN TRY
    IF EXISTS (SELECT 1 FROM dbo.chartOfAccounts WHERE companyId IN (@A, @B, @C))
        RAISERROR('Test companies -9701/-9702/-9703 already have accounts — aborting.', 16, 1);
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @A;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @B;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @C;

    -- Custom non-current accounts for A (code convention 12xx / 22xx).
    INSERT INTO dbo.chartOfAccounts (companyId, code, name, accountType, normalBalance, parentAccountId, isPostable, level)
    SELECT @A, '1205', N'Equipo', 'ASSET', 'D', accountId, 1, 2 FROM dbo.chartOfAccounts WHERE companyId=@A AND code='1';
    INSERT INTO dbo.chartOfAccounts (companyId, code, name, accountType, normalBalance, parentAccountId, isPostable, level)
    SELECT @A, '2205', N'Préstamo largo plazo', 'LIABILITY', 'C', accountId, 1, 2 FROM dbo.chartOfAccounts WHERE companyId=@A AND code='2';

    DECLARE @j TABLE (companyId INT, entryDate DATE, status NVARCHAR(10), dr NVARCHAR(10), cr NVARCHAR(10), amt DECIMAL(12,2));
    INSERT INTO @j VALUES
        (@A, '2025-12-15', 'POSTED', '1101', '4105',   40),
        (@A, '2026-09-01', 'POSTED', '1101', '3105', 1000),
        (@A, '2026-09-05', 'POSTED', '1101', '4105',  100),
        (@A, '2026-09-06', 'POSTED', '1105', '4105',  100),
        (@A, '2026-09-06', 'POSTED', '5120', '1105', 4.20),
        (@A, '2026-09-07', 'POSTED', '5115', '1101',   50),
        (@A, '2026-09-08', 'POSTED', '5105', '1105',   50),
        (@A, '2026-09-09', 'VOID',   '1101', '4105',  999),
        (@A, '2026-10-05', 'POSTED', '1101', '4105',    7),
        (@A, '2026-09-10', 'POSTED', '1105', '2105',  300),
        (@A, '2026-09-11', 'POSTED', '1105', '2205',  500),
        (@A, '2026-09-12', 'POSTED', '1205', '1105',  200),
        (@B, '2026-09-01', 'POSTED', '1101', '3105', 5000);

    DECLARE @cid INT, @ed DATE, @st NVARCHAR(10), @dr NVARCHAR(10), @cr NVARCHAR(10), @amt DECIMAL(12,2), @num INT, @eid INT;
    DECLARE jc CURSOR LOCAL FAST_FORWARD FOR SELECT companyId, entryDate, status, dr, cr, amt FROM @j;
    OPEN jc; FETCH NEXT FROM jc INTO @cid, @ed, @st, @dr, @cr, @amt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @num = ISNULL(MAX(entryNumber), 0) + 1 FROM dbo.journalEntries WHERE companyId = @cid;
        INSERT INTO dbo.journalEntries (companyId, entryNumber, entryDate, description, referenceType, status, totalDebit, totalCredit)
        VALUES (@cid, @num, @ed, N'TEST BG', 'manual', @st, @amt, @amt);
        SET @eid = SCOPE_IDENTITY();
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
        SELECT @eid, accountId, @amt, 0 FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = @dr;
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
        SELECT @eid, accountId, 0, @amt FROM dbo.chartOfAccounts WHERE companyId = @cid AND code = @cr;
        FETCH NEXT FROM jc INTO @cid, @ed, @st, @dr, @cr, @amt;
    END
    CLOSE jc; DEALLOCATE jc;

    DECLARE @jA NVARCHAR(MAX) = dbo.fn_journalEntries_balanceSheetJson(@A, '2026-09-30');
    DECLARE @jA0 NVARCHAR(MAX) = dbo.fn_journalEntries_balanceSheetJson(@A, '2025-12-31');
    DECLARE @jB NVARCHAR(MAX) = dbo.fn_journalEntries_balanceSheetJson(@B, '2026-09-30');
    DECLARE @jC NVARCHAR(MAX) = dbo.fn_journalEntries_balanceSheetJson(@C, '2026-09-30');

    -- Shape
    INSERT INTO @checks (name, expected, actual) SELECT N'JSON is valid and has every section', '1/1/1/1',
        CAST(ISJSON(@jA) AS NVARCHAR(1)) + '/' +
        CASE WHEN JSON_QUERY(@jA, '$.assets.current') IS NOT NULL AND JSON_QUERY(@jA, '$.assets.nonCurrent') IS NOT NULL THEN '1' ELSE '0' END + '/' +
        CASE WHEN JSON_QUERY(@jA, '$.liabilities.current') IS NOT NULL AND JSON_QUERY(@jA, '$.liabilities.nonCurrent') IS NOT NULL THEN '1' ELSE '0' END + '/' +
        CASE WHEN JSON_QUERY(@jA, '$.equity.accounts') IS NOT NULL THEN '1' ELSE '0' END;

    -- Tests 2/3/4/5/6/7: Caja and Bancos (VOID and after-cutoff excluded)
    INSERT INTO @checks (name, expected, actual) SELECT N'Caja 1101 (40+1000+100-50; VOID 999 and 10-05 excluded)', '1090.00',
        ISNULL((SELECT JSON_VALUE(value, '$.balance') FROM OPENJSON(@jA, '$.assets.current') WHERE JSON_VALUE(value, '$.code') = '1101'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'Bancos 1105 (100-4.20-50+300+500-200)', '645.80',
        ISNULL((SELECT JSON_VALUE(value, '$.balance') FROM OPENJSON(@jA, '$.assets.current') WHERE JSON_VALUE(value, '$.code') = '1105'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'Equipo 1205 is non-current', '200.00',
        ISNULL((SELECT JSON_VALUE(value, '$.balance') FROM OPENJSON(@jA, '$.assets.nonCurrent') WHERE JSON_VALUE(value, '$.code') = '1205'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'assets.total', '1935.80', JSON_VALUE(@jA, '$.assets.total');
    INSERT INTO @checks (name, expected, actual) SELECT N'liabilities current CxP / non-current Préstamo / total', '300.00/500.00/800.00',
        ISNULL((SELECT JSON_VALUE(value, '$.balance') FROM OPENJSON(@jA, '$.liabilities.current') WHERE JSON_VALUE(value, '$.code') = '2105'), '(none)') + '/' +
        ISNULL((SELECT JSON_VALUE(value, '$.balance') FROM OPENJSON(@jA, '$.liabilities.nonCurrent') WHERE JSON_VALUE(value, '$.code') = '2205'), '(none)') + '/' +
        JSON_VALUE(@jA, '$.liabilities.total');
    INSERT INTO @checks (name, expected, actual) SELECT N'equity: Capital social / prior years / current year / total', '1000.00/40.00/95.80/1135.80',
        ISNULL((SELECT JSON_VALUE(value, '$.balance') FROM OPENJSON(@jA, '$.equity.accounts') WHERE JSON_VALUE(value, '$.code') = '3105'), '(none)') + '/' +
        JSON_VALUE(@jA, '$.equity.priorYearsResult') + '/' + JSON_VALUE(@jA, '$.equity.currentYearResult') + '/' + JSON_VALUE(@jA, '$.equity.total');

    -- Test 11: equation
    INSERT INTO @checks (name, expected, actual) SELECT N'Test 11 Activo = Pasivo + Capital (totals / balanced)', '1935.80/1935.80/true',
        JSON_VALUE(@jA, '$.assets.total') + '/' + JSON_VALUE(@jA, '$.totalLiabilitiesAndEquity') + '/' + JSON_VALUE(@jA, '$.balanced');

    -- Test 12 (preview of Step 11): current-year result = P&L Jan 1 … cutoff, computed independently
    DECLARE @pl DECIMAL(14,2) = (
        SELECT SUM(CASE WHEN a.accountType = 'INCOME' THEN l.credit - l.debit ELSE l.debit - l.credit END * CASE WHEN a.accountType = 'INCOME' THEN 1 ELSE -1 END)
        FROM dbo.journalEntries e JOIN dbo.journalEntryLines l ON l.journalEntryId = e.entryId
        JOIN dbo.chartOfAccounts a ON a.accountId = l.accountId
        WHERE e.companyId = @A AND e.status = 'POSTED' AND e.entryDate BETWEEN '2026-01-01' AND '2026-09-30'
          AND a.accountType IN ('INCOME', 'EXPENSE'));
    INSERT INTO @checks (name, expected, actual) SELECT N'Test 12 currentYearResult = independent P&L (200 - 104.20)', CAST(@pl AS NVARCHAR(20)),
        JSON_VALUE(@jA, '$.equity.currentYearResult');

    -- Comparison date (previous year end)
    INSERT INTO @checks (name, expected, actual) SELECT N'2025-12-31: Caja / current year / prior / balanced', '40.00/40.00/0.00/true',
        ISNULL((SELECT JSON_VALUE(value, '$.balance') FROM OPENJSON(@jA0, '$.assets.current') WHERE JSON_VALUE(value, '$.code') = '1101'), '(none)') + '/' +
        JSON_VALUE(@jA0, '$.equity.currentYearResult') + '/' + JSON_VALUE(@jA0, '$.equity.priorYearsResult') + '/' + JSON_VALUE(@jA0, '$.balanced');

    -- Test 1: opening only (cutoff on the opening date, after a prior-year sale)
    DECLARE @jOpen NVARCHAR(MAX) = dbo.fn_journalEntries_balanceSheetJson(@A, '2026-09-01');
    INSERT INTO @checks (name, expected, actual) SELECT N'Test 1 at 2026-09-01: assets / current-year result / balanced', '1040.00/0.00/true',
        JSON_VALUE(@jOpen, '$.assets.total') + '/' + JSON_VALUE(@jOpen, '$.equity.currentYearResult') + '/' + JSON_VALUE(@jOpen, '$.balanced');

    -- Test 8: isolation
    INSERT INTO @checks (name, expected, actual) SELECT N'Test 8 company B only its own 5000 / balanced', '5000.00/true',
        JSON_VALUE(@jB, '$.assets.total') + '/' + JSON_VALUE(@jB, '$.balanced');
    INSERT INTO @checks (name, expected, actual) SELECT N'Test 8 company A has none of B''s 5000', '0',
        CAST((SELECT COUNT(*) FROM OPENJSON(@jA, '$.assets.current') WHERE TRY_CONVERT(DECIMAL(14,2), JSON_VALUE(value, '$.balance')) >= 5000) AS NVARCHAR(5));

    -- Empty company
    INSERT INTO @checks (name, expected, actual) SELECT N'empty company: arrays empty, totals 0, balanced', '0/0.00/0.00/true',
        CAST((SELECT COUNT(*) FROM OPENJSON(@jC, '$.assets.current')) AS NVARCHAR(5)) + '/' +
        JSON_VALUE(@jC, '$.assets.total') + '/' + JSON_VALUE(@jC, '$.totalLiabilitiesAndEquity') + '/' + JSON_VALUE(@jC, '$.balanced');

    -- Zero-balance accounts omitted (A's 1101 at 2025-12-14 → nothing)
    INSERT INTO @checks (name, expected, actual) SELECT N'no activity before 2025-12-15 → no lines', '0',
        CAST((SELECT COUNT(*) FROM dbo.fn_journalEntries_balanceSheet(@A, '2025-12-14') WHERE section <> 'RESULT') AS NVARCHAR(5));
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
            THEN 'STEP 8 GATE (SQL): ALL ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS PASS'
            ELSE 'STEP 8 GATE (SQL): ' + CAST(SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) AS NVARCHAR(10))
                 + ' OF ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS FAIL' END AS summary,
       (SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId IN (-9701, -9702, -9703))
     + (SELECT COUNT(*) FROM dbo.journalEntries  WHERE companyId IN (-9701, -9702, -9703)) AS leftoverTestRows
FROM @checks;
