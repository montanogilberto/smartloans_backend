-- ============================================================
-- 2026-10-16c: one table for every discount a customer can get —
-- dbo.posRewardCatalogItems. See docs/promotions_rewards_analysis.md.
--
--   rewardType      what it is                          paid with
--   coupon_b2g1     promo code at checkout (2X1)         nothing (code + rules)
--   discount_fixed  $X off                               points balance
--   discount_pct    X% off                               points balance
--   free_product    stamp card: buy N, next one free     units bought of that product
--
-- New columns:
--   code              coupon code (unique per company), NULL for the rest
--   startAtUtc/endAtUtc  optional validity window
--   firstPurchaseOnly coupon only for a client's first sale (enforced server-side)
--   requiredUnits     stamp card: purchases of freeProductId needed. Replaces the
--                     old trick of storing units in requiredPoints (kept as-is
--                     until the POS front / menuLaundy read requiredUnits).
--   freeProductId     free_product: the free product; coupon_b2g1: the only
--                     product it discounts (NULL = every product).
--
-- Data: copies dbo.promotions (+ promotionTargets) into the catalog and
-- points income.promotionId at the new catalogItemId. dbo.promotions and
-- dbo.promotionTargets are NOT dropped here — see
-- 2026-10-16d_drop_promotions_tables.sql (run after the POS has used the
-- catalog coupons for a while).
--
-- Run order: this file → sql/sp_posRewards.sql → sql/sp_posRewardFreeProductStatus.sql
-- → sql/sp_whatsappCustomerRewards.sql → sql/sp_promotions.sql
-- → sql/sp_income_applyDiscounts.sql  (full order: sql/migrations/README_pos_rewards.md)
-- Safe to re-run.
-- ============================================================

IF COL_LENGTH('dbo.posRewardCatalogItems', 'code') IS NULL
    ALTER TABLE [dbo].[posRewardCatalogItems] ADD code VARCHAR(30) NULL;
IF COL_LENGTH('dbo.posRewardCatalogItems', 'startAtUtc') IS NULL
    ALTER TABLE [dbo].[posRewardCatalogItems] ADD startAtUtc DATETIME2(0) NULL;
IF COL_LENGTH('dbo.posRewardCatalogItems', 'endAtUtc') IS NULL
    ALTER TABLE [dbo].[posRewardCatalogItems] ADD endAtUtc DATETIME2(0) NULL;
IF COL_LENGTH('dbo.posRewardCatalogItems', 'firstPurchaseOnly') IS NULL
    ALTER TABLE [dbo].[posRewardCatalogItems] ADD firstPurchaseOnly BIT NOT NULL
        CONSTRAINT DF_posRewardCatalogItems_firstPurchaseOnly DEFAULT (0);
IF COL_LENGTH('dbo.posRewardCatalogItems', 'requiredUnits') IS NULL
    ALTER TABLE [dbo].[posRewardCatalogItems] ADD requiredUnits DECIMAL(12,2) NULL;
GO

IF OBJECT_ID('dbo.CK_posRewardCatalogItems_rewardType', 'C') IS NOT NULL
    ALTER TABLE [dbo].[posRewardCatalogItems] DROP CONSTRAINT CK_posRewardCatalogItems_rewardType;
IF OBJECT_ID('dbo.CK_posRewardCatalogItems_valueByType', 'C') IS NOT NULL
    ALTER TABLE [dbo].[posRewardCatalogItems] DROP CONSTRAINT CK_posRewardCatalogItems_valueByType;
GO
ALTER TABLE [dbo].[posRewardCatalogItems] ADD
    CONSTRAINT CK_posRewardCatalogItems_rewardType
        CHECK (rewardType IN ('discount_fixed','discount_pct','free_product','coupon_b2g1')),
    CONSTRAINT CK_posRewardCatalogItems_valueByType CHECK (
        (rewardType IN ('discount_fixed','discount_pct') AND discountValue IS NOT NULL)
        OR (rewardType = 'free_product' AND freeProductId IS NOT NULL)
        OR (rewardType = 'coupon_b2g1' AND code IS NOT NULL)
    );
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_posRewardCatalogItems_company_code')
    CREATE UNIQUE INDEX UQ_posRewardCatalogItems_company_code
        ON [dbo].[posRewardCatalogItems] (companyId, code) WHERE code IS NOT NULL;
GO

-- Stamp cards: units needed = requiredPoints / pointsPerUnit, the conversion
-- sp_posRewardRedemptions_redeem used (pointsPerUnit missing → requiredPoints).
UPDATE c SET requiredUnits = CAST(CASE WHEN ISNULL(r.pointsPerUnit, 0) > 0
                                       THEN c.requiredPoints / r.pointsPerUnit
                                       ELSE c.requiredPoints END AS DECIMAL(12,2))
FROM [dbo].[posRewardCatalogItems] c
OUTER APPLY (SELECT TOP 1 pr.pointsPerUnit FROM [dbo].[posRewardProductRates] pr
             WHERE pr.companyId = c.companyId AND pr.productId = c.freeProductId AND pr.isActive = 1) r
WHERE c.rewardType = 'free_product' AND c.requiredUnits IS NULL;
GO

-- ── Copy dbo.promotions into the catalog ──
IF OBJECT_ID('dbo.promotions', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM [dbo].[promotions] WHERE promoType <> 'B2G1')
        RAISERROR('dbo.promotions has a promoType other than B2G1; map it before migrating. Nothing copied.', 16, 1);
    ELSE IF OBJECT_ID('dbo.promotionTargets', 'U') IS NOT NULL AND EXISTS (
        SELECT 1 FROM [dbo].[promotionTargets] WHERE targetType = 'PRODUCT'
        GROUP BY promotionId HAVING COUNT(*) > 1)
        RAISERROR('A promotion targets several products; one catalog coupon covers one product or all. Nothing copied.', 16, 1);
    ELSE
    BEGIN
        -- promotions.description exists only after the 2026-10-16 assistant migration.
        DECLARE @descCol NVARCHAR(50) = CASE WHEN COL_LENGTH('dbo.promotions', 'description') IS NULL
                                             THEN N'NULL' ELSE N'p.description' END;
        DECLARE @targets NVARCHAR(400) = CASE WHEN OBJECT_ID('dbo.promotionTargets', 'U') IS NULL THEN N'NULL' ELSE
            N'(SELECT TOP 1 t.productId FROM dbo.promotionTargets t
                WHERE t.promotionId = p.promotionId AND t.targetType = ''PRODUCT''
                  AND NOT EXISTS (SELECT 1 FROM dbo.promotionTargets a WHERE a.promotionId = p.promotionId AND a.targetType = ''ALL''))' END;
        -- The 2X1 row is the POS welcome coupon: "one 2x1 on the client's
        -- first purchase" (POSVending CartPage.tsx WELCOME_COUPON_CODE).
        DECLARE @sql NVARCHAR(MAX) = N'
        INSERT INTO dbo.posRewardCatalogItems
            (companyId, name, rewardType, requiredPoints, discountValue, freeProductId, isActive, description,
             code, startAtUtc, endAtUtc, firstPurchaseOnly)
        SELECT p.companyId, LEFT(p.name, 120), ''coupon_b2g1'', 0, NULL, ' + @targets + N', p.isActive,
               LEFT(' + @descCol + N', 255), UPPER(p.code), p.startAtUtc, p.endAtUtc,
               CASE WHEN UPPER(p.code) = ''2X1'' THEN 1 ELSE 0 END
        FROM dbo.promotions p
        WHERE NOT EXISTS (SELECT 1 FROM dbo.posRewardCatalogItems c
                          WHERE c.companyId = p.companyId AND c.code = UPPER(p.code));';
        EXEC sp_executesql @sql;

        -- Past sales: promotionId now names the catalog row. Matching on the
        -- stored promotionCode too keeps a re-run from remapping twice.
        UPDATE i SET promotionId = c.catalogItemId
        FROM [dbo].[income] i
        JOIN [dbo].[promotions] p ON p.promotionId = i.promotionId AND UPPER(p.code) = UPPER(i.promotionCode)
        JOIN [dbo].[posRewardCatalogItems] c ON c.companyId = p.companyId AND c.code = UPPER(p.code);
    END
END
GO

-- Superseded the same day (commit 125b703): targets now live on the coupon row.
IF OBJECT_ID('dbo.sp_promotionTargets', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_promotionTargets;
GO
