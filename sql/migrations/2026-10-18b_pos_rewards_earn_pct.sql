-- ============================================================
-- 2026-10-18b: POS points as a % of what the client paid (GMO Lavandería 2.5%).
--
-- Before: points = SUM(pointsPerUnit * quantity) per product. Laundry prices
-- depend on the option (Básico $40 / Medio $50 / Carga alta $70 of the same
-- product), so a per-unit rate can't give a fixed % back.
--
-- After, for a company with dbo.posRewardSettings.earnPct:
--   points = ROUND(net paid on eligible lines * earnPct / 100, 2)
--   eligible line  = its product has an active posRewardProductRates row
--                    (the rates table now says WHAT earns; pointsPerUnit is
--                    only used by companies without earnPct)
--   net paid       = incomeDetails.netAmount, written by
--                    sp_income_applyDiscounts (after the coupon, the free
--                    stamp unit and the points discount); sales without
--                    discounts split income.total by line price.
--   1 point = $1 of reward, so the points rewards become 10 pts → $10,
--   25 → $25, 50 → $50.
-- Companies without a posRewardSettings row keep points per unit, unchanged.
--
-- Data, company 1 only (dbo.companies 'Lavanderia', checked by name):
--   * earnPct = 2.5
--   * discount_fixed rewards still at the old 10-points-per-peso price
--     (requiredPoints = discountValue * 10) move to requiredPoints = discountValue.
--     Rows already changed by hand are left alone.
-- Runs in POST /posRewards/migrate after 2026-10-18. Safe to re-run.
-- ============================================================

IF OBJECT_ID('dbo.posRewardSettings', 'U') IS NULL
CREATE TABLE [dbo].[posRewardSettings] (
    companyId  INT           NOT NULL CONSTRAINT PK_posRewardSettings PRIMARY KEY,
    earnPct    DECIMAL(5,2)  NULL,      -- % of the net paid on eligible lines; NULL = points per unit
    updated_at DATETIME2     NOT NULL CONSTRAINT DF_posRewardSettings_updated DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_posRewardSettings_earnPct CHECK (earnPct IS NULL OR (earnPct > 0 AND earnPct <= 100))
);
GO

-- Net amount the client paid for the line, after every discount on the sale.
IF COL_LENGTH('dbo.incomeDetails', 'netAmount') IS NULL
    ALTER TABLE [dbo].[incomeDetails] ADD netAmount DECIMAL(12,2) NULL;
GO

IF EXISTS (SELECT 1 FROM [dbo].[companies] WHERE companyId = 1 AND name LIKE N'%Lavander%')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [dbo].[posRewardSettings] WHERE companyId = 1)
        INSERT INTO [dbo].[posRewardSettings] (companyId, earnPct) VALUES (1, 2.5);

    UPDATE [dbo].[posRewardCatalogItems]
    SET requiredPoints = discountValue, updated_at = GETUTCDATE()
    WHERE companyId = 1 AND rewardType = 'discount_fixed'
      AND discountValue IN (10, 25, 50) AND requiredPoints = discountValue * 10;
    PRINT CONCAT('Company 1: earnPct 2.5; ', @@ROWCOUNT, ' points reward(s) repriced to 1 pt = $1.');
END
ELSE
    PRINT 'Company 1 is not the laundry; no earnPct or catalog change made.';
GO
