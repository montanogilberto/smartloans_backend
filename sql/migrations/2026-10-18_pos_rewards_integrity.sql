-- ============================================================
-- 2026-10-18: POS rewards integrity (review of the unified catalog model).
--
--   * one applied reward per sale: filtered unique index on
--     posRewardRedemptions(incomeId) — a retried or concurrent apply can't
--     redeem twice for the same sale.
--   * CHECK constraints for the rules that live in one row:
--       catalog values by rewardType, validity window, rate >= 0,
--       balance >= 0, ledger points / txType-direction pairs,
--       redemption pointsSpent >= 0.
-- Rules that need other rows (balance covers the reward, stamps earned,
-- first purchase, same company) stay in the SPs, under the client lock.
--
-- Rows already breaking a rule don't block the deploy: that constraint is
-- added WITH NOCHECK (enforced for new writes, old rows untouched) and the
-- migration PRINTs which one, so they can be fixed and the constraint
-- re-checked (ALTER TABLE ... WITH CHECK CHECK CONSTRAINT ...).
-- Runs after 2026-10-16c (sql/migrations/README_pos_rewards.md). Safe to re-run.
-- ============================================================

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_posRewardRedemptions_income_applied')
BEGIN
    IF EXISTS (SELECT incomeId FROM [dbo].[posRewardRedemptions]
               WHERE incomeId IS NOT NULL AND status = 'applied'
               GROUP BY incomeId HAVING COUNT(*) > 1)
        PRINT 'UQ_posRewardRedemptions_income_applied NOT created: some sales have several applied redemptions.';
    ELSE
        CREATE UNIQUE INDEX UQ_posRewardRedemptions_income_applied
            ON [dbo].[posRewardRedemptions] (incomeId) WHERE incomeId IS NOT NULL AND status = 'applied';
END
GO

DECLARE @checks TABLE (tbl SYSNAME, name SYSNAME, expr NVARCHAR(MAX));
INSERT INTO @checks VALUES
(N'posRewardCatalogItems', N'CK_posRewardCatalogItems_values', N'
       (rewardType = ''discount_fixed'' AND requiredPoints > 0 AND discountValue > 0)
    OR (rewardType = ''discount_pct''   AND requiredPoints > 0 AND discountValue > 0 AND discountValue <= 100)
    OR (rewardType = ''free_product''   AND ISNULL(requiredUnits, requiredPoints) > 0)
    OR (rewardType = ''coupon_b2g1''    AND requiredPoints = 0)'),
(N'posRewardCatalogItems', N'CK_posRewardCatalogItems_dates',
    N'startAtUtc IS NULL OR endAtUtc IS NULL OR endAtUtc > startAtUtc'),
(N'posRewardProductRates', N'CK_posRewardProductRates_points', N'pointsPerUnit >= 0'),
(N'posRewardBalances',     N'CK_posRewardBalances_nonNegative', N'balance >= 0'),
-- A delete reversal can post a 0-point ADJUSTMENT when the points were already spent.
(N'posRewardTransactions', N'CK_posRewardTransactions_points',
    N'points > 0 OR (txType = ''ADJUSTMENT'' AND points = 0)'),
(N'posRewardTransactions', N'CK_posRewardTransactions_txDirection', N'
       (txType = ''EARN'' AND direction = ''C'')
    OR (txType IN (''REDEEM'', ''EXPIRE'') AND direction = ''D'')
    OR txType = ''ADJUSTMENT'''),
(N'posRewardRedemptions',  N'CK_posRewardRedemptions_pointsSpent', N'pointsSpent >= 0');

DECLARE @tbl SYSNAME, @name SYSNAME, @expr NVARCHAR(MAX), @bad INT, @sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT tbl, name, expr FROM @checks;
OPEN c;
FETCH NEXT FROM c INTO @tbl, @name, @expr;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID(N'dbo.' + @name, 'C') IS NULL
    BEGIN
        SET @sql = N'SELECT @bad = COUNT(*) FROM dbo.' + QUOTENAME(@tbl) + N' WHERE NOT (' + @expr + N')';
        EXEC sp_executesql @sql, N'@bad INT OUTPUT', @bad = @bad OUTPUT;
        SET @sql = N'ALTER TABLE dbo.' + QUOTENAME(@tbl)
                 + CASE WHEN @bad > 0 THEN N' WITH NOCHECK' ELSE N' WITH CHECK' END
                 + N' ADD CONSTRAINT ' + QUOTENAME(@name) + N' CHECK (' + @expr + N')';
        EXEC sp_executesql @sql;
        IF @bad > 0
            PRINT CONCAT(@name, N' added WITH NOCHECK: ', @bad, N' existing row(s) break it.');
    END
    FETCH NEXT FROM c INTO @tbl, @name, @expr;
END
CLOSE c;
DEALLOCATE c;
GO
