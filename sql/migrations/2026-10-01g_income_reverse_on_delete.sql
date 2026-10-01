-- =============================================================================
-- Step 5 — deleting a sale reverses its accounting and its points
-- =============================================================================
-- Forward-only. NOT YET EXECUTED — run manually against the live DB.
-- Roadmap: POSVending/docs/accounting-module.md, Step 5.
-- Test:    sql/tests/2026-10-01g_income_reverse_on_delete_test.sql
-- Hook:    modules/income.py calls it after a successful sp_income action=2.
--
-- OWNER DECISIONS (2026-10-01):
--   Q6 Rewards redemption = PURELY PROMOTIONAL → no journal entry is ever
--      created for points (earn, redeem, adjust, expire, reversal).
--   Sale deleted → its journal entries are VOIDed automatically.
--   Sale deleted → the points it earned are reversed.
--
-- WHY: sp_income action=2 hard-deletes the sale (income, incomeDetails,
-- cashRegisterMovements) but left its POSTED journal entries (Caja/Bancos and
-- Ventas kept counting a sale that no longer exists) and its earned points.
--
-- WHAT: dbo.sp_income_reverseOnDelete @incomeId
--   1. Journal: POSTED entries with referenceType IN ('income','income_commission')
--      and referenceId = @incomeId → status 'VOID' (the only mutation the
--      journal allows; nothing is deleted).
--   2. POS rewards (posRewardTransactions/posRewardBalances): the ticket's EARN
--      row (referenceType 'ticket', referenceId = incomeId) is taken back with
--      an ADJUSTMENT/D row. The schema allows referenceType ticket|redemption|
--      manual only, and the filtered unique index UQ_posRewardTransactions_ticket
--      reserves 'ticket' for the EARN row, so the reversal is
--      referenceType 'manual' + referenceId = incomeId + description
--      'Reversa venta eliminada #<incomeId>' (that pair is the idempotency key).
--   3. Loyalty rewards (rewardTransactions/rewardPoints, modules/rewards.py
--      earn_points_for_income: txType 'earn', referenceId = '<incomeId>'):
--      taken back with txType 'adjustment', points negative,
--      referenceId 'reversal:<incomeId>' (idempotency key).
--   Balances never go below zero: if the client already spent those points,
--   only what is left is taken back and the rest is reported as *Shortfall*
--   (also written in the adjustment's description).
--   Refuses to run while the income row still exists (it is a post-delete
--   step, never a way to cancel a live sale's books).
--   Idempotent. Savepoint-aware (testable inside a rolled-back transaction).
--   Returns ONE plain row: voidedEntries, posPointsReversed, posPointsShortfall,
--   loyaltyPointsReversed, loyaltyPointsShortfall, alreadyReversed.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_income_reverseOnDelete]
    @incomeId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @voided INT = 0,
            @posReversed DECIMAL(12,2) = 0, @posShort DECIMAL(12,2) = 0,
            @loyReversed INT = 0, @loyShort INT = 0,
            @alreadyReversed BIT = 0;
    DECLARE @tc INT = @@TRANCOUNT;
    DECLARE @tag NVARCHAR(60) = N'Reversa venta eliminada #' + CAST(@incomeId AS NVARCHAR(12));
    DECLARE @loyRef NVARCHAR(100) = N'reversal:' + CAST(@incomeId AS NVARCHAR(12));

    IF @incomeId IS NULL
    BEGIN
        RAISERROR('incomeId es requerido.', 16, 1);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM [dbo].[income] WHERE incomeId = @incomeId)
    BEGIN
        RAISERROR('La venta todavía existe: la reversa solo corre después de eliminarla.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        IF @tc = 0 BEGIN TRANSACTION; ELSE SAVE TRANSACTION revIncome;

        -- 1) Journal: VOID the sale and its commission.
        UPDATE [dbo].[journalEntries]
        SET status = 'VOID', updated_at = GETUTCDATE()
        WHERE referenceType IN ('income', 'income_commission')
          AND referenceId = @incomeId
          AND status = 'POSTED';
        SET @voided = @@ROWCOUNT;

        -- 2) POS rewards.
        DECLARE @pc INT, @pcl INT, @earned DECIMAL(12,2), @bal DECIMAL(12,2), @nb DECIMAL(12,2);
        SELECT TOP 1 @pc = companyId, @pcl = clientId, @earned = points
        FROM [dbo].[posRewardTransactions]
        WHERE txType = 'EARN' AND referenceType = 'ticket' AND referenceId = @incomeId;

        IF @pc IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[posRewardTransactions]
                       WHERE companyId = @pc AND txType = 'ADJUSTMENT' AND referenceType = 'manual'
                         AND referenceId = @incomeId AND description LIKE @tag + N'%')
                SET @alreadyReversed = 1;
            ELSE
            BEGIN
                SELECT @bal = balance FROM [dbo].[posRewardBalances] WITH (UPDLOCK, HOLDLOCK)
                WHERE companyId = @pc AND clientId = @pcl;
                SET @bal = ISNULL(@bal, 0);
                SET @posReversed = CASE WHEN @earned <= @bal THEN @earned WHEN @bal > 0 THEN @bal ELSE 0 END;
                SET @posShort = @earned - @posReversed;

                DECLARE @negPos DECIMAL(12,2) = -@posReversed;
                EXEC [dbo].[sp_posRewardBalances_applyDelta]
                    @companyId = @pc, @clientId = @pcl,
                    @pointsDelta = @negPos, @earnedDelta = @negPos, @redeemedDelta = 0,
                    @newBalance = @nb OUTPUT;

                INSERT INTO [dbo].[posRewardTransactions]
                    (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
                VALUES
                    (@pc, @pcl, 'ADJUSTMENT', 'D', @posReversed, 'manual', @incomeId, ISNULL(@nb, 0),
                     @tag + CASE WHEN @posShort > 0
                                 THEN N' (faltante ' + CAST(@posShort AS NVARCHAR(20)) + N' pts ya canjeados)'
                                 ELSE N'' END);
            END
        END

        -- 3) Loyalty rewards (rewardTransactions / rewardPoints).
        DECLARE @rc INT, @rcl INT, @rEarned INT, @rBal INT;
        SELECT TOP 1 @rc = companyId, @rcl = clientId
        FROM [dbo].[rewardTransactions]
        WHERE txType = 'earn' AND referenceId = CAST(@incomeId AS NVARCHAR(100));

        IF @rc IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[rewardTransactions]
                       WHERE companyId = @rc AND txType = 'adjustment' AND referenceId = @loyRef)
                SET @alreadyReversed = 1;
            ELSE
            BEGIN
                SELECT @rEarned = ISNULL(SUM(points), 0) FROM [dbo].[rewardTransactions]
                WHERE companyId = @rc AND clientId = @rcl AND txType = 'earn'
                  AND referenceId = CAST(@incomeId AS NVARCHAR(100));
                SELECT @rBal = balance FROM [dbo].[rewardPoints] WITH (UPDLOCK, HOLDLOCK)
                WHERE companyId = @rc AND clientId = @rcl;
                SET @rBal = ISNULL(@rBal, 0);
                SET @loyReversed = CASE WHEN @rEarned <= @rBal THEN @rEarned WHEN @rBal > 0 THEN @rBal ELSE 0 END;
                SET @loyShort = @rEarned - @loyReversed;

                UPDATE [dbo].[rewardPoints]
                SET balance = balance - @loyReversed,
                    lifetimeEarned = lifetimeEarned - @loyReversed,
                    lastActivity = GETUTCDATE(), updated_at = GETUTCDATE()
                WHERE companyId = @rc AND clientId = @rcl;

                INSERT INTO [dbo].[rewardTransactions]
                    (companyId, clientId, ruleId, txType, points, balanceAfter, referenceId, description, createdBy)
                VALUES
                    (@rc, @rcl, NULL, 'adjustment', -@loyReversed,
                     ISNULL((SELECT balance FROM [dbo].[rewardPoints] WHERE companyId = @rc AND clientId = @rcl), 0),
                     @loyRef,
                     @tag + CASE WHEN @loyShort > 0
                                 THEN N' (faltante ' + CAST(@loyShort AS NVARCHAR(20)) + N' pts ya canjeados)'
                                 ELSE N'' END,
                     NULL);
            END
        END

        IF @tc = 0 COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @tc = 0 AND @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF @tc > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION revIncome;
        THROW;
    END CATCH

    SELECT @voided AS voidedEntries,
           @posReversed AS posPointsReversed, @posShort AS posPointsShortfall,
           @loyReversed AS loyaltyPointsReversed, @loyShort AS loyaltyPointsShortfall,
           @alreadyReversed AS alreadyReversed;
END
GO

-- Verify (expect 1).
SELECT CASE WHEN OBJECT_ID('dbo.sp_income_reverseOnDelete', 'P') IS NOT NULL THEN 1 ELSE 0 END AS reverseOnDeleteDeployed;

-- Sales ALREADY deleted whose journal entries are still POSTED (report only —
-- not repaired here; Step 10 reconciliation decides, explicitly).
SELECT e.companyId, e.referenceType, COUNT(*) AS postedEntriesForDeletedSales, SUM(e.totalDebit) AS amount
FROM dbo.journalEntries e
WHERE e.status = 'POSTED'
  AND e.referenceType IN ('income', 'income_commission')
  AND NOT EXISTS (SELECT 1 FROM dbo.income i WHERE i.incomeId = e.referenceId)
GROUP BY e.companyId, e.referenceType;
GO
