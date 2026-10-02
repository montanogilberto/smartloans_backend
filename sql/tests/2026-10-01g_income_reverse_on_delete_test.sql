-- =============================================================================
-- TEST — Step 5: sp_income_reverseOnDelete (journal VOID + points reversal)
-- Roadmap Step 5 gate (POSVending/docs/accounting-module.md)
-- =============================================================================
-- SAFE TO RUN ON PRODUCTION: one transaction, ALWAYS rolled back (the SP uses a
-- savepoint inside a caller's transaction). Fake companies -9401 / -9402, fake
-- client -9401, and incomeIds 1,000,000 above the current max (never real).
--
--   X  sale with income + commission entries, 15 POS pts + 15 loyalty pts, balances 15
--   Y  another sale of company A (must stay untouched)
--   Z  sale whose 20 POS pts were partly spent (balance only 5) → shortfall 15
--   W  an income row that still EXISTS → SP must refuse
--   B  company -9402 has its own EARN on another sale → untouched
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

DECLARE @A INT = -9401, @B INT = -9402, @CL INT = -9401, @CLZ INT = -9402, @CLB INT = -9403;
DECLARE @checks TABLE (seq INT IDENTITY, name NVARCHAR(200), expected NVARCHAR(80), actual NVARCHAR(80));
DECLARE @out TABLE (voidedEntries INT, posPointsReversed DECIMAL(12,2), posPointsShortfall DECIMAL(12,2),
                    loyaltyPointsReversed INT, loyaltyPointsShortfall INT, alreadyReversed BIT);
DECLARE @r1 NVARCHAR(200), @r2 NVARCHAR(200), @r3 NVARCHAR(200);

INSERT INTO @checks (name, expected, actual)
SELECT N'sp_income_reverseOnDelete deployed', '1',
       CASE WHEN OBJECT_ID('dbo.sp_income_reverseOnDelete', 'P') IS NOT NULL THEN '1' ELSE '0' END;
IF OBJECT_ID('dbo.sp_income_reverseOnDelete', 'P') IS NULL GOTO Report;

BEGIN TRANSACTION;
BEGIN TRY
    IF EXISTS (SELECT 1 FROM dbo.chartOfAccounts WHERE companyId IN (@A, @B))
        RAISERROR('Test companies -9401/-9402 already have accounts — aborting.', 16, 1);
    EXEC dbo.sp_chartOfAccounts_seed @companyId = @A;

    DECLARE @base INT = (SELECT ISNULL(MAX(incomeId), 0) + 1000000 FROM dbo.income);
    DECLARE @X INT = @base + 1, @Y INT = @base + 2, @Z INT = @base + 3, @BI INT = @base + 4;

    -- ── Journal: X income + commission, Y income (company A) ──────────────────
    DECLARE @j TABLE (refType NVARCHAR(30), refId INT, dr NVARCHAR(10), cr NVARCHAR(10), amt DECIMAL(12,2));
    INSERT INTO @j VALUES ('income', @X, '1105', '4105', 100), ('income_commission', @X, '5120', '1105', 4.20),
                          ('income', @Y, '1101', '4105', 50);
    DECLARE @rt NVARCHAR(30), @rid INT, @dr NVARCHAR(10), @cr NVARCHAR(10), @amt DECIMAL(12,2), @num INT, @eid INT;
    DECLARE jc CURSOR LOCAL FAST_FORWARD FOR SELECT refType, refId, dr, cr, amt FROM @j;
    OPEN jc; FETCH NEXT FROM jc INTO @rt, @rid, @dr, @cr, @amt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @num = ISNULL(MAX(entryNumber), 0) + 1 FROM dbo.journalEntries WHERE companyId = @A;
        INSERT INTO dbo.journalEntries (companyId, entryNumber, entryDate, description, referenceType, referenceId, status, totalDebit, totalCredit)
        VALUES (@A, @num, '2026-09-30', N'TEST', @rt, @rid, 'POSTED', @amt, @amt);
        SET @eid = SCOPE_IDENTITY();
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
        SELECT @eid, accountId, @amt, 0 FROM dbo.chartOfAccounts WHERE companyId = @A AND code = @dr;
        INSERT INTO dbo.journalEntryLines (journalEntryId, accountId, debit, credit)
        SELECT @eid, accountId, 0, @amt FROM dbo.chartOfAccounts WHERE companyId = @A AND code = @cr;
        FETCH NEXT FROM jc INTO @rt, @rid, @dr, @cr, @amt;
    END
    CLOSE jc; DEALLOCATE jc;

    -- ── Points: X earned 15 POS + 15 loyalty; Z earned 20 POS but balance is 5 ─
    INSERT INTO dbo.posRewardBalances (companyId, clientId, balance, lifetimeEarned, lifetimeRedeemed) VALUES
        (@A, @CL, 15, 15, 0), (@A, @CLZ, 5, 20, 15), (@B, @CLB, 7, 7, 0);
    INSERT INTO dbo.posRewardTransactions (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description) VALUES
        (@A, @CL,  'EARN', 'C', 15, 'ticket', @X,  15, N'TEST X'),
        (@A, @CLZ, 'EARN', 'C', 20, 'ticket', @Z,  20, N'TEST Z'),
        (@B, @CLB, 'EARN', 'C',  7, 'ticket', @BI,  7, N'TEST B');
    INSERT INTO dbo.rewardPoints (companyId, clientId, balance, lifetimeEarned, lifetimeRedeemed) VALUES (@A, @CL, 15, 15, 0);
    INSERT INTO dbo.rewardTransactions (companyId, clientId, ruleId, txType, points, balanceAfter, referenceId, description)
    VALUES (@A, @CL, NULL, 'earn', 15, 15, CAST(@X AS NVARCHAR(100)), N'TEST X');

    DECLARE @journalCount0 INT = (SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId IN (@A, @B));

    -- ── R1: reverse X ─────────────────────────────────────────────────────────
    DELETE FROM @out;
    INSERT INTO @out EXEC dbo.sp_income_reverseOnDelete @incomeId = @X;
    SELECT @r1 = CAST(voidedEntries AS NVARCHAR(5)) + '/' + CAST(posPointsReversed AS NVARCHAR(20)) + '/' + CAST(posPointsShortfall AS NVARCHAR(20))
               + '/' + CAST(loyaltyPointsReversed AS NVARCHAR(10)) + '/' + CAST(loyaltyPointsShortfall AS NVARCHAR(10)) + '/' + CAST(alreadyReversed AS NVARCHAR(1)) FROM @out;
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 voided/posRev/posShort/loyRev/loyShort/already', '2/15.00/0.00/15/0/0', @r1;
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 X income + commission entries are VOID', '2',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceId=@X AND status='VOID') AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 Y (other sale) still POSTED', '1',
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId=@A AND referenceId=@Y AND status='POSTED') AS NVARCHAR(5));
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 no journal entry created (count unchanged)', CAST(@journalCount0 AS NVARCHAR(10)),
        CAST((SELECT COUNT(*) FROM dbo.journalEntries WHERE companyId IN (@A, @B)) AS NVARCHAR(10));
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 X no longer counts: 1105 Bancos / 4105 Ventas', '(none)/50.00',
        ISNULL((SELECT CAST(balance AS NVARCHAR(30)) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30') WHERE code='1105'), '(none)') + '/' +
        ISNULL((SELECT CAST(balance AS NVARCHAR(30)) FROM dbo.fn_journalEntries_accountTotals(@A, '2026-09-30') WHERE code='4105'), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 POS balance / lifetimeEarned', '0.00/0.00',
        (SELECT CAST(balance AS NVARCHAR(20)) + '/' + CAST(lifetimeEarned AS NVARCHAR(20)) FROM dbo.posRewardBalances WHERE companyId=@A AND clientId=@CL);
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 POS ADJUSTMENT row: D/15/manual/ref X', 'D/15.00/manual/1',
        ISNULL((SELECT direction + '/' + CAST(points AS NVARCHAR(20)) + '/' + referenceType + '/' + CASE WHEN referenceId=@X THEN '1' ELSE '0' END
                FROM dbo.posRewardTransactions WHERE companyId=@A AND txType='ADJUSTMENT' AND referenceId=@X), '(none)');
    INSERT INTO @checks (name, expected, actual) SELECT N'R1 loyalty balance / adjustment points', '0/-15',
        CAST((SELECT balance FROM dbo.rewardPoints WHERE companyId=@A AND clientId=@CL) AS NVARCHAR(10)) + '/' +
        ISNULL((SELECT CAST(points AS NVARCHAR(10)) FROM dbo.rewardTransactions WHERE companyId=@A AND txType='adjustment' AND referenceId=N'reversal:' + CAST(@X AS NVARCHAR(12))), '(none)');

    -- ── R2: same sale again → idempotent ─────────────────────────────────────
    DELETE FROM @out;
    INSERT INTO @out EXEC dbo.sp_income_reverseOnDelete @incomeId = @X;
    SELECT @r2 = CAST(voidedEntries AS NVARCHAR(5)) + '/' + CAST(posPointsReversed AS NVARCHAR(20)) + '/' + CAST(loyaltyPointsReversed AS NVARCHAR(10))
               + '/' + CAST(alreadyReversed AS NVARCHAR(1)) FROM @out;
    INSERT INTO @checks (name, expected, actual) SELECT N'R2 re-run: voided/posRev/loyRev/already', '0/0.00/0/1', @r2;
    INSERT INTO @checks (name, expected, actual) SELECT N'R2 still one POS + one loyalty reversal row', '1/1',
        CAST((SELECT COUNT(*) FROM dbo.posRewardTransactions WHERE companyId=@A AND txType='ADJUSTMENT' AND referenceId=@X) AS NVARCHAR(5)) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.rewardTransactions WHERE companyId=@A AND txType='adjustment' AND referenceId=N'reversal:' + CAST(@X AS NVARCHAR(12))) AS NVARCHAR(5));

    -- ── R3: points already spent → shortfall, never negative ─────────────────
    DELETE FROM @out;
    INSERT INTO @out EXEC dbo.sp_income_reverseOnDelete @incomeId = @Z;
    SELECT @r3 = CAST(posPointsReversed AS NVARCHAR(20)) + '/' + CAST(posPointsShortfall AS NVARCHAR(20)) FROM @out;
    INSERT INTO @checks (name, expected, actual) SELECT N'R3 Z reversed/shortfall (balance was 5 of 20)', '5.00/15.00', @r3;
    INSERT INTO @checks (name, expected, actual) SELECT N'R3 Z balance not negative', '0.00',
        (SELECT CAST(balance AS NVARCHAR(20)) FROM dbo.posRewardBalances WHERE companyId=@A AND clientId=@CLZ);

    -- ── R4: refuses while the sale still exists ──────────────────────────────
    DECLARE @W INT, @refused NVARCHAR(10) = 'no';
    INSERT INTO dbo.income (total, paymentMethod, paymentDate, userId, clientId, companyId) VALUES (10, 'Efectivo', GETUTCDATE(), 0, 0, @A);
    SET @W = SCOPE_IDENTITY();
    BEGIN TRY
        EXEC dbo.sp_income_reverseOnDelete @incomeId = @W;
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE N'%todavía existe%' SET @refused = 'yes';
    END CATCH
    INSERT INTO @checks (name, expected, actual) SELECT N'R4 refuses while the income row exists', 'yes', @refused;

    -- ── Isolation ────────────────────────────────────────────────────────────
    INSERT INTO @checks (name, expected, actual) SELECT N'company B points untouched', '7.00/0',
        (SELECT CAST(balance AS NVARCHAR(20)) FROM dbo.posRewardBalances WHERE companyId=@B AND clientId=@CLB) + '/' +
        CAST((SELECT COUNT(*) FROM dbo.posRewardTransactions WHERE companyId=@B AND txType='ADJUSTMENT') AS NVARCHAR(5));
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
            THEN 'STEP 5 GATE (SQL): ALL ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS PASS'
            ELSE 'STEP 5 GATE (SQL): ' + CAST(SUM(CASE WHEN ISNULL(expected,'') = ISNULL(actual,'') THEN 0 ELSE 1 END) AS NVARCHAR(10))
                 + ' OF ' + CAST(COUNT(*) AS NVARCHAR(10)) + ' CHECKS FAIL' END AS summary,
       (SELECT COUNT(*) FROM dbo.chartOfAccounts       WHERE companyId IN (-9401, -9402))
     + (SELECT COUNT(*) FROM dbo.journalEntries        WHERE companyId IN (-9401, -9402))
     + (SELECT COUNT(*) FROM dbo.posRewardTransactions WHERE companyId IN (-9401, -9402))
     + (SELECT COUNT(*) FROM dbo.rewardTransactions    WHERE companyId IN (-9401, -9402))
     + (SELECT COUNT(*) FROM dbo.income                WHERE companyId IN (-9401, -9402)) AS leftoverTestRows
FROM @checks;
