-- =============================================================================
-- TEST — Step 3: sp_journalEntries duplicate guard + VOID + isolation
-- Roadmap Step 3 gate (POSVending/docs/accounting-module.md §7.3)
-- =============================================================================
-- Runs the REAL sp_journalEntries against two fake companies (-9201, -9202).
-- NOT wrapped in an outer transaction: when sp_journalEntries rejects a post,
-- its CATCH does ROLLBACK TRAN, which would also undo (and end) any outer test
-- transaction. Instead the script deletes every fake row it creates — before
-- starting (leftovers of an aborted run) and at the end, also after an error.
-- Only rows of companyId -9201/-9202 are ever deleted. Final line prints
-- leftoverTestRows (must be 0).
--
-- OUTPUT: each EXEC of sp_journalEntries returns its own small jsonResult set
-- (rejections show {"error":"Ya existe un asiento POSTED ... duplicado rechazado"}).
-- The gate is read from the LAST THREE result sets: checks, summary, leftovers.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @A INT = -9201, @B INT = -9202;
DECLARE @checks TABLE (seq INT IDENTITY, name NVARCHAR(200), expected NVARCHAR(60), actual NVARCHAR(60));

-- ── Cleanup helper (run before and after) ───────────────────────────────────
DELETE l FROM dbo.journalEntryLines l JOIN dbo.journalEntries e ON e.entryId = l.journalEntryId WHERE e.companyId IN (@A, @B);
DELETE FROM dbo.journalEntries  WHERE companyId IN (@A, @B);
DELETE FROM dbo.chartOfAccounts WHERE companyId IN (@A, @B);
DELETE FROM dbo.companies       WHERE companyId IN (@A, @B);

INSERT INTO @checks (name, expected, actual)
SELECT N'duplicate guard deployed', '1',
       CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_journalEntries')) LIKE '%duplicado rechazado%' THEN '1' ELSE '0' END;

BEGIN TRY
    -- ── Fixture ───────────────────────────────────────────────────────────────
    SET IDENTITY_INSERT dbo.companies ON;
    INSERT INTO dbo.companies (companyId, name) VALUES (@A, 'TEST accounting A'), (@B, 'TEST accounting B');
    SET IDENTITY_INSERT dbo.companies OFF;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @A;
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @B;

    DECLARE @a1101 INT = (SELECT accountId FROM dbo.chartOfAccounts WHERE companyId=@A AND code='1101');
    DECLARE @a4105 INT = (SELECT accountId FROM dbo.chartOfAccounts WHERE companyId=@A AND code='4105');
    DECLARE @a5110 INT = (SELECT accountId FROM dbo.chartOfAccounts WHERE companyId=@A AND code='5110');
    DECLARE @b1105 INT = (SELECT accountId FROM dbo.chartOfAccounts WHERE companyId=@B AND code='1105');
    DECLARE @b4105 INT = (SELECT accountId FROM dbo.chartOfAccounts WHERE companyId=@B AND code='4105');

    DECLARE @incomeA NVARCHAR(MAX) = N'{"journalEntries":[{"action":1,"companyId":' + CAST(@A AS NVARCHAR(12))
        + N',"entryDate":"2026-09-30","description":"TEST income 900001","referenceType":"income","referenceId":900001,"lines":['
        + N'{"accountId":' + CAST(@a1101 AS NVARCHAR(12)) + N',"debit":100,"credit":0},'
        + N'{"accountId":' + CAST(@a4105 AS NVARCHAR(12)) + N',"debit":0,"credit":100}]}]}';
    DECLARE @expenseA NVARCHAR(MAX) = N'{"journalEntries":[{"action":1,"companyId":' + CAST(@A AS NVARCHAR(12))
        + N',"entryDate":"2026-09-30","description":"TEST expense 900001","referenceType":"expense","referenceId":900001,"lines":['
        + N'{"accountId":' + CAST(@a5110 AS NVARCHAR(12)) + N',"debit":40,"credit":0},'
        + N'{"accountId":' + CAST(@a1101 AS NVARCHAR(12)) + N',"debit":0,"credit":40}]}]}';
    DECLARE @incomeB NVARCHAR(MAX) = N'{"journalEntries":[{"action":1,"companyId":' + CAST(@B AS NVARCHAR(12))
        + N',"entryDate":"2026-09-30","description":"TEST income 900001 (B)","referenceType":"income","referenceId":900001,"lines":['
        + N'{"accountId":' + CAST(@b1105 AS NVARCHAR(12)) + N',"debit":70,"credit":0},'
        + N'{"accountId":' + CAST(@b4105 AS NVARCHAR(12)) + N',"debit":0,"credit":70}]}]}';
    DECLARE @manualA NVARCHAR(MAX) = N'{"journalEntries":[{"action":1,"companyId":' + CAST(@A AS NVARCHAR(12))
        + N',"entryDate":"2026-09-30","description":"TEST manual","referenceType":"manual","lines":['
        + N'{"accountId":' + CAST(@a1101 AS NVARCHAR(12)) + N',"debit":5,"credit":0},'
        + N'{"accountId":' + CAST(@a4105 AS NVARCHAR(12)) + N',"debit":0,"credit":5}]}]}';

    -- T1 first post → accepted
    EXEC dbo.sp_journalEntries @pjsonfile = @incomeA;
    INSERT INTO @checks (name, expected, actual) SELECT N'T1 first income post accepted (POSTED count)', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income' AND referenceId=900001 AND status='POSTED') AS NVARCHAR(10));

    -- T2 same movement again → rejected
    EXEC dbo.sp_journalEntries @pjsonfile = @incomeA;
    INSERT INTO @checks (name, expected, actual) SELECT N'T2 duplicate income post rejected (still 1)', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income' AND referenceId=900001) AS NVARCHAR(10));

    -- T3 same referenceId, different referenceType → accepted
    EXEC dbo.sp_journalEntries @pjsonfile = @expenseA;
    INSERT INTO @checks (name, expected, actual) SELECT N'T3 expense with same referenceId accepted', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='expense' AND referenceId=900001 AND status='POSTED') AS NVARCHAR(10));

    -- T4 other company, same reference → accepted (isolation)
    EXEC dbo.sp_journalEntries @pjsonfile = @incomeB;
    INSERT INTO @checks (name, expected, actual) SELECT N'T4 company B same reference accepted', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@B AND referenceType='income' AND referenceId=900001 AND status='POSTED') AS NVARCHAR(10));

    -- T5 VOID A's income, then re-post → accepted
    DECLARE @voidId INT = (SELECT entryId FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income' AND referenceId=900001 AND status='POSTED');
    DECLARE @voidJson NVARCHAR(MAX) = N'{"journalEntries":[{"action":2,"entryId":' + CAST(@voidId AS NVARCHAR(12))
        + N',"companyId":' + CAST(@A AS NVARCHAR(12)) + N',"status":"VOID"}]}';
    EXEC dbo.sp_journalEntries @pjsonfile = @voidJson;
    EXEC dbo.sp_journalEntries @pjsonfile = @incomeA;
    INSERT INTO @checks (name, expected, actual) SELECT N'T5 after VOID, re-post accepted (VOID/POSTED)', '1/1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income' AND referenceId=900001 AND status='VOID') AS NVARCHAR(10)) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income' AND referenceId=900001 AND status='POSTED') AS NVARCHAR(10));

    -- T6 post again while a POSTED one exists → rejected
    EXEC dbo.sp_journalEntries @pjsonfile = @incomeA;
    INSERT INTO @checks (name, expected, actual) SELECT N'T6 second re-post rejected (still 1 POSTED)', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='income' AND referenceId=900001 AND status='POSTED') AS NVARCHAR(10));

    -- T7 manual entries without referenceId are never blocked
    EXEC dbo.sp_journalEntries @pjsonfile = @manualA;
    EXEC dbo.sp_journalEntries @pjsonfile = @manualA;
    INSERT INTO @checks (name, expected, actual) SELECT N'T7 two manual entries both accepted', '2',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceType='manual' AND status='POSTED') AS NVARCHAR(10));

    -- T8 every entry balances; A's POSTED ledger = 100 + 40 + 5 + 5
    INSERT INTO @checks (name, expected, actual) SELECT N'T8 unbalanced entries', '0',
        CAST((SELECT COUNT(*) FROM (SELECT e.entryId FROM dbo.journalEntries e JOIN dbo.journalEntryLines l ON l.journalEntryId=e.entryId
                                    WHERE e.companyId IN (@A,@B) GROUP BY e.entryId HAVING SUM(l.debit) <> SUM(l.credit)) x) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'T8 company A POSTED debits (100+40+5+5)', '150.00',
        CAST((SELECT SUM(l.debit) FROM dbo.journalEntries e JOIN dbo.journalEntryLines l ON l.journalEntryId=e.entryId
              WHERE e.companyId=@A AND e.status='POSTED') AS NVARCHAR(30));
    INSERT INTO @checks (name, expected, actual) SELECT N'T8 company A Caja balance via fn (100-40+5+5)', '70.00',
        ISNULL((SELECT CAST(balance AS NVARCHAR(30)) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30') WHERE code='1101'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'T8 company B unaffected by A (Bancos)', '70.00',
        ISNULL((SELECT CAST(balance AS NVARCHAR(30)) FROM dbo.fn_journalEntries_accountTotals(@B, '2026-09-30') WHERE code='1105'), '(none)');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO @checks (name, expected, actual) VALUES (N'TEST ERROR: ' + ERROR_MESSAGE(), 'no error', 'error');
END CATCH

-- ── Cleanup (always) ─────────────────────────────────────────────────────────
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
            THEN 'STEP 3 GATE (SQL): ALL ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS PASS'
            ELSE 'STEP 3 GATE (SQL): ' + CAST(SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) AS NVARCHAR(10))
                 + ' OF ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS FAIL' END AS summary
FROM @checks;

SELECT (SELECT COUNT(*) FROM dbo.companies       WHERE companyId IN (-9201, -9202))
     + (SELECT COUNT(*) FROM dbo.chartOfAccounts WHERE companyId IN (-9201, -9202))
     + (SELECT COUNT(*) FROM dbo.journalEntries  WHERE companyId IN (-9201, -9202)) AS leftoverTestRows;
