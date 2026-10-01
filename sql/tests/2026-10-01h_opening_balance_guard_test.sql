-- =============================================================================
-- TEST — Step 6: opening balances (one per company, balance-sheet only)
-- Roadmap Step 6 gate (POSVending/docs/accounting-module.md §7.4)
-- =============================================================================
-- Runs the REAL sp_journalEntries against fake companies -9501 / -9502.
-- Not wrapped in an outer transaction (a rejected post rolls back any outer
-- transaction), so it deletes every fake row it creates — before starting and
-- at the end, also after an error. Only companyId -9501/-9502 rows are deleted.
-- Each EXEC prints a small jsonResult; read the LAST THREE result sets.
--
--   A (-9501): O1 opening Dr Caja 1000 / Cr Capital 1000 (2026-09-01) → accepted
--              O2 a second opening                                    → rejected
--              O5 cutoff 2026-08-31 sees nothing; 2026-09-01 sees it
--              O6 Activo = Pasivo + Capital + Resultado, Resultado = 0
--              O7 + cash sale 100 → Activo 1100 = 0 + 1000 + 100
--              O8 VOID the opening → a new opening is accepted
--   B (-9502): O3 opening using an INCOME account                     → rejected
--              O4 valid opening (A's does not block B)                → accepted
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @A INT = -9501, @B INT = -9502;
DECLARE @checks TABLE (seq INT IDENTITY, name NVARCHAR(200), expected NVARCHAR(80), actual NVARCHAR(80));

DELETE l FROM dbo.journalEntryLines l JOIN dbo.journalEntries e ON e.entryId = l.journalEntryId WHERE e.companyId IN (@A, @B);
DELETE FROM dbo.journalEntries  WHERE companyId IN (@A, @B);
DELETE FROM dbo.chartOfAccounts WHERE companyId IN (@A, @B);
DELETE FROM dbo.companies       WHERE companyId IN (@A, @B);

INSERT INTO @checks (name, expected, actual)
SELECT N'opening guard deployed', '1',
       CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries')) LIKE '%saldos iniciales%' THEN '1' ELSE '0' END;

BEGIN TRY
    SET IDENTITY_INSERT dbo.companies ON;
    INSERT INTO dbo.companies (companyId, name) VALUES (@A, 'TEST opening A'), (@B, 'TEST opening B');
    SET IDENTITY_INSERT dbo.companies OFF;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @A;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @B;

    DECLARE @a1101 NVARCHAR(12) = (SELECT CAST(accountId AS NVARCHAR(12)) FROM dbo.chartOfAccounts WHERE companyId=@A AND code='1101');
    DECLARE @a3105 NVARCHAR(12) = (SELECT CAST(accountId AS NVARCHAR(12)) FROM dbo.chartOfAccounts WHERE companyId=@A AND code='3105');
    DECLARE @a4105 NVARCHAR(12) = (SELECT CAST(accountId AS NVARCHAR(12)) FROM dbo.chartOfAccounts WHERE companyId=@A AND code='4105');
    DECLARE @b1101 NVARCHAR(12) = (SELECT CAST(accountId AS NVARCHAR(12)) FROM dbo.chartOfAccounts WHERE companyId=@B AND code='1101');
    DECLARE @b1105 NVARCHAR(12) = (SELECT CAST(accountId AS NVARCHAR(12)) FROM dbo.chartOfAccounts WHERE companyId=@B AND code='1105');
    DECLARE @b2105 NVARCHAR(12) = (SELECT CAST(accountId AS NVARCHAR(12)) FROM dbo.chartOfAccounts WHERE companyId=@B AND code='2105');
    DECLARE @b3105 NVARCHAR(12) = (SELECT CAST(accountId AS NVARCHAR(12)) FROM dbo.chartOfAccounts WHERE companyId=@B AND code='3105');
    DECLARE @b4105 NVARCHAR(12) = (SELECT CAST(accountId AS NVARCHAR(12)) FROM dbo.chartOfAccounts WHERE companyId=@B AND code='4105');
    DECLARE @sa NVARCHAR(12) = CAST(@A AS NVARCHAR(12)), @sb NVARCHAR(12) = CAST(@B AS NVARCHAR(12));

    DECLARE @openA NVARCHAR(MAX) = N'{"journalEntries":[{"action":1,"companyId":' + @sa + N',"entryDate":"2026-09-01","description":"Saldos iniciales","referenceType":"opening_balance","lines":['
        + N'{"accountId":' + @a1101 + N',"debit":1000,"credit":0},{"accountId":' + @a3105 + N',"debit":0,"credit":1000}]}]}';
    DECLARE @openBbad NVARCHAR(MAX) = N'{"journalEntries":[{"action":1,"companyId":' + @sb + N',"entryDate":"2026-09-01","description":"Saldos iniciales","referenceType":"opening_balance","lines":['
        + N'{"accountId":' + @b1101 + N',"debit":500,"credit":0},{"accountId":' + @b4105 + N',"debit":0,"credit":500}]}]}';
    DECLARE @openB NVARCHAR(MAX) = N'{"journalEntries":[{"action":1,"companyId":' + @sb + N',"entryDate":"2026-09-01","description":"Saldos iniciales","referenceType":"opening_balance","lines":['
        + N'{"accountId":' + @b1105 + N',"debit":500,"credit":0},{"accountId":' + @b2105 + N',"debit":0,"credit":200},{"accountId":' + @b3105 + N',"debit":0,"credit":300}]}]}';
    DECLARE @saleA NVARCHAR(MAX) = N'{"journalEntries":[{"action":1,"companyId":' + @sa + N',"entryDate":"2026-09-15","description":"Venta efectivo","referenceType":"manual","lines":['
        + N'{"accountId":' + @a1101 + N',"debit":100,"credit":0},{"accountId":' + @a4105 + N',"debit":0,"credit":100}]}]}';

    -- O1 / O2
    EXEC dbo.sp_journalEntries @pjsonfile = @openA;
    INSERT INTO @checks (name, expected, actual) SELECT N'O1 opening accepted (POSTED openings A)', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='opening_balance' AND status='POSTED') AS NVARCHAR(5));
    EXEC dbo.sp_journalEntries @pjsonfile = @openA;
    INSERT INTO @checks (name, expected, actual) SELECT N'O2 second opening rejected (still 1)', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='opening_balance') AS NVARCHAR(5));

    -- O3 / O4
    EXEC dbo.sp_journalEntries @pjsonfile = @openBbad;
    INSERT INTO @checks (name, expected, actual) SELECT N'O3 opening with an INCOME account rejected', '0',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@B AND referenceType='opening_balance') AS NVARCHAR(5));
    EXEC dbo.sp_journalEntries @pjsonfile = @openB;
    INSERT INTO @checks (name, expected, actual) SELECT N'O4 company B opening accepted (A does not block B)', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@B AND referenceType='opening_balance' AND status='POSTED') AS NVARCHAR(5));

    -- O5 cutoff
    INSERT INTO @checks (name, expected, actual) SELECT N'O5 cutoff 2026-08-31 sees nothing', '0',
        CAST((SELECT COUNT(*) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-08-31')) AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'O5 cutoff 2026-09-01: Caja / Capital social', '1000.00/1000.00',
        ISNULL((SELECT CAST(balance AS NVARCHAR(20)) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-01') WHERE code='1101'), '(none)') + '/' +
        ISNULL((SELECT CAST(balance AS NVARCHAR(20)) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-01') WHERE code='3105'), '(none)');

    -- O6 equation with only the opening
    DECLARE @eq TABLE (label NVARCHAR(10), activo DECIMAL(14,2), pasivo DECIMAL(14,2), capital DECIMAL(14,2), resultado DECIMAL(14,2));
    INSERT INTO @eq
    SELECT 'A-open',
        ISNULL(SUM(CASE WHEN accountType='ASSET' THEN balance END), 0),
        ISNULL(SUM(CASE WHEN accountType='LIABILITY' THEN balance END), 0),
        ISNULL(SUM(CASE WHEN accountType='EQUITY' THEN balance END), 0),
        ISNULL(SUM(CASE WHEN accountType='INCOME' THEN balance END), 0) - ISNULL(SUM(CASE WHEN accountType='EXPENSE' THEN balance END), 0)
    FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30');
    INSERT INTO @checks (name, expected, actual) SELECT N'O6 A Activo/Pasivo/Capital/Resultado (opening only)', '1000.00/0.00/1000.00/0.00',
        (SELECT CAST(activo AS NVARCHAR(20)) + '/' + CAST(pasivo AS NVARCHAR(20)) + '/' + CAST(capital AS NVARCHAR(20)) + '/' + CAST(resultado AS NVARCHAR(20)) FROM @eq WHERE label='A-open');
    INSERT INTO @checks (name, expected, actual) SELECT N'O6 A Activo = Pasivo + Capital + Resultado', '1',
        (SELECT CASE WHEN activo = pasivo + capital + resultado THEN '1' ELSE '0' END FROM @eq WHERE label='A-open');

    -- O7 + cash sale
    EXEC dbo.sp_journalEntries @pjsonfile = @saleA;
    INSERT INTO @eq
    SELECT 'A-sale',
        ISNULL(SUM(CASE WHEN accountType='ASSET' THEN balance END), 0),
        ISNULL(SUM(CASE WHEN accountType='LIABILITY' THEN balance END), 0),
        ISNULL(SUM(CASE WHEN accountType='EQUITY' THEN balance END), 0),
        ISNULL(SUM(CASE WHEN accountType='INCOME' THEN balance END), 0) - ISNULL(SUM(CASE WHEN accountType='EXPENSE' THEN balance END), 0)
    FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30');
    INSERT INTO @checks (name, expected, actual) SELECT N'O7 A after cash sale: Activo/Pasivo/Capital/Resultado', '1100.00/0.00/1000.00/100.00',
        (SELECT CAST(activo AS NVARCHAR(20)) + '/' + CAST(pasivo AS NVARCHAR(20)) + '/' + CAST(capital AS NVARCHAR(20)) + '/' + CAST(resultado AS NVARCHAR(20)) FROM @eq WHERE label='A-sale');
    INSERT INTO @checks (name, expected, actual) SELECT N'O7 A equation still holds', '1',
        (SELECT CASE WHEN activo = pasivo + capital + resultado THEN '1' ELSE '0' END FROM @eq WHERE label='A-sale');

    -- O8 VOID the opening → a corrected one may be posted
    DECLARE @openId NVARCHAR(12) = (SELECT CAST(entryId AS NVARCHAR(12)) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='opening_balance' AND status='POSTED');
    DECLARE @voidA NVARCHAR(MAX) = N'{"journalEntries":[{"action":2,"entryId":' + @openId + N',"companyId":' + @sa + N',"status":"VOID"}]}';
    EXEC dbo.sp_journalEntries @pjsonfile = @voidA;
    EXEC dbo.sp_journalEntries @pjsonfile = @openA;
    INSERT INTO @checks (name, expected, actual) SELECT N'O8 after VOID a new opening is accepted (VOID/POSTED)', '1/1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='opening_balance' AND status='VOID') AS NVARCHAR(5)) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='opening_balance' AND status='POSTED') AS NVARCHAR(5));

    -- O9 company B equation (with a liability)
    INSERT INTO @eq
    SELECT 'B',
        ISNULL(SUM(CASE WHEN accountType='ASSET' THEN balance END), 0),
        ISNULL(SUM(CASE WHEN accountType='LIABILITY' THEN balance END), 0),
        ISNULL(SUM(CASE WHEN accountType='EQUITY' THEN balance END), 0),
        ISNULL(SUM(CASE WHEN accountType='INCOME' THEN balance END), 0) - ISNULL(SUM(CASE WHEN accountType='EXPENSE' THEN balance END), 0)
    FROM dbo.fn_journalEntries_accountTotals(@B, '2026-09-30');
    INSERT INTO @checks (name, expected, actual) SELECT N'O9 B Activo/Pasivo/Capital/Resultado', '500.00/200.00/300.00/0.00',
        (SELECT CAST(activo AS NVARCHAR(20)) + '/' + CAST(pasivo AS NVARCHAR(20)) + '/' + CAST(capital AS NVARCHAR(20)) + '/' + CAST(resultado AS NVARCHAR(20)) FROM @eq WHERE label='B');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @checks (name, expected, actual) VALUES (N'TEST ERROR: ' + ERROR_MESSAGE(), 'no error', 'error');
END CATCH

IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
BEGIN TRY SET IDENTITY_INSERT dbo.companies OFF; END TRY BEGIN CATCH END CATCH;
DELETE l FROM dbo.journalEntryLines l JOIN dbo.journalEntries e ON e.entryId = l.journalEntryId WHERE e.companyId IN (@A, @B);
DELETE FROM dbo.journalEntries  WHERE companyId IN (@A, @B);
DELETE FROM dbo.chartOfAccounts WHERE companyId IN (@A, @B);
DELETE FROM dbo.companies       WHERE companyId IN (@A, @B);

SELECT seq, CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 'PASS' ELSE 'FAIL' END AS result,
       name, expected, actual
FROM @checks ORDER BY seq;

SELECT CASE WHEN SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) = 0
            THEN 'STEP 6 GATE (SQL): ALL ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS PASS'
            ELSE 'STEP 6 GATE (SQL): ' + CAST(SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) AS NVARCHAR(10))
                 + ' OF ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS FAIL' END AS summary,
       (SELECT COUNT(*) FROM dbo.companies       WHERE companyId IN (-9501, -9502))
     + (SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId IN (-9501, -9502))
     + (SELECT COUNT(*) FROM dbo.journalEntries  WHERE companyId IN (-9501, -9502)) AS leftoverTestRows
FROM @checks;
