-- ============================================================
-- 2026-10-16d: drop dbo.promotions and dbo.promotionTargets.
-- Run MANUALLY after 2026-10-16c and once the POS has charged sales with the
-- catalog coupons (income.promotionId pointing at posRewardCatalogItems).
-- Last step of sql/migrations/README_pos_rewards.md.
--
-- Fails, changing nothing, if a coupon was not copied or if any object other
-- than the legacy ones below still references the tables.
--   sp_income             keeps a dormant B2G1 block reading dbo.promotions; it
--                         never runs because modules/income.py strips
--                         promotionCode before calling sp_income and applies
--                         coupons with sp_income_applyDiscounts instead.
--   sp_income_apply_promo no callers anywhere (POS, agents); dropped here.
--
-- The table is dbo.promotionTargets (renamed from promotion_targets after the
-- 2026-08-15 snapshot; its FK FK_promotion_targets_promotions kept the old
-- name). It must be dropped BEFORE dbo.promotions, or that FK blocks the drop.
-- ============================================================

IF OBJECT_ID('dbo.promotions', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[promotions] p
               WHERE NOT EXISTS (SELECT 1 FROM [dbo].[posRewardCatalogItems] c
                                 WHERE c.companyId = p.companyId AND c.code = UPPER(p.code)))
    BEGIN
        RAISERROR('Some promotions are not in posRewardCatalogItems yet; run 2026-10-16c first. Nothing dropped.', 16, 1);
        RETURN;
    END

    DECLARE @users NVARCHAR(MAX) = (
        SELECT STUFF((
            SELECT DISTINCT N', ' + OBJECT_NAME(d.referencing_id)
            FROM sys.sql_expression_dependencies d
            WHERE d.referenced_id IN (OBJECT_ID('dbo.promotions'), OBJECT_ID('dbo.promotionTargets'))
              AND OBJECT_NAME(d.referencing_id) NOT IN ('sp_income', 'sp_income_apply_promo')
            FOR XML PATH('')), 1, 2, N''));
    IF @users IS NOT NULL
    BEGIN
        DECLARE @msg NVARCHAR(MAX) = N'Still referenced by: ' + @users + N'. Nothing dropped.';
        RAISERROR(@msg, 16, 1);
        RETURN;
    END

    IF OBJECT_ID('dbo.sp_income_apply_promo', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_income_apply_promo;
    IF OBJECT_ID('dbo.promotionTargets', 'U') IS NOT NULL DROP TABLE [dbo].[promotionTargets];
    DROP TABLE [dbo].[promotions];
    PRINT 'dbo.promotions and dbo.promotionTargets dropped.';
END
GO
