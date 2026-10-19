-- ============================================================
-- POS loyalty rewards — earn points from POS tickets, redeem
-- against an admin-managed catalog. Logically and structurally
-- separate from modules/rewards.py (loan-behavior rewardTransactions/
-- rewardBalances) and from any arcade chip ledger: no FK, no shared
-- endpoint, no conversion function between them.
--
-- Specs: posgmo-factory/tests/prd_posRewardProductRate.json,
--        prd_posRewardCatalogItem.json, prd_posRewardBalance.json,
--        prd_posRewardTransaction.json, prd_posRewardRedemption.json
--
-- Run this single file once against the target DB (tables use
-- IF NOT EXISTS, procedures DROP+CREATE, safe to re-run). Internal
-- order matters: posRewardBalances before posRewardTransactions/
-- posRewardRedemptions (they call sp_posRewardBalances_applyDelta),
-- posRewardCatalogItems before posRewardRedemptions (FK).
-- ============================================================

-- ── Table: posRewardProductRates ────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardProductRates')
CREATE TABLE [dbo].[posRewardProductRates] (
    rateId          INT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    productId       INT            NOT NULL,
    pointsPerUnit   DECIMAL(12,2)  NOT NULL,
    isActive        BIT            NOT NULL DEFAULT 1,
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2      NULL
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_posRewardProductRates_company_product')
    CREATE UNIQUE INDEX UQ_posRewardProductRates_company_product
        ON [dbo].[posRewardProductRates] (companyId, productId);
GO

-- ── Table: posRewardCatalogItems ────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardCatalogItems')
CREATE TABLE [dbo].[posRewardCatalogItems] (
    catalogItemId   INT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    name            NVARCHAR(120)  NOT NULL,
    rewardType      NVARCHAR(20)   NOT NULL,  -- discount_fixed | discount_pct | free_product | coupon_b2g1
    requiredPoints  DECIMAL(12,2)  NOT NULL,  -- points (discount_*); 0 for coupons
    discountValue   DECIMAL(12,2)  NULL,      -- MXN (discount_fixed) or 0-100 (discount_pct)
    freeProductId   INT            NULL,      -- free_product: the free product; coupon_b2g1: only product discounted (NULL = all)
    isActive        BIT            NOT NULL DEFAULT 1,
    description     NVARCHAR(255)  NULL,
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2      NULL,
    code            VARCHAR(30)    NULL,      -- coupon_b2g1: code typed at checkout (unique per company)
    startAtUtc      DATETIME2(0)   NULL,
    endAtUtc        DATETIME2(0)   NULL,
    firstPurchaseOnly BIT          NOT NULL CONSTRAINT DF_posRewardCatalogItems_firstPurchaseOnly DEFAULT (0),
    requiredUnits   DECIMAL(12,2)  NULL,      -- free_product: purchases of freeProductId per free unit
    CONSTRAINT CK_posRewardCatalogItems_rewardType
        CHECK (rewardType IN ('discount_fixed','discount_pct','free_product','coupon_b2g1')),
    CONSTRAINT CK_posRewardCatalogItems_valueByType CHECK (
        (rewardType IN ('discount_fixed','discount_pct') AND discountValue IS NOT NULL)
        OR (rewardType = 'free_product' AND freeProductId IS NOT NULL)
        OR (rewardType = 'coupon_b2g1' AND code IS NOT NULL)
    )
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_posRewardCatalogItems_company')
    CREATE INDEX IX_posRewardCatalogItems_company
        ON [dbo].[posRewardCatalogItems] (companyId, isActive);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_posRewardCatalogItems_company_code')
    CREATE UNIQUE INDEX UQ_posRewardCatalogItems_company_code
        ON [dbo].[posRewardCatalogItems] (companyId, code) WHERE code IS NOT NULL;
GO

-- ── Table: posRewardBalances (materialized projection) ──────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardBalances')
CREATE TABLE [dbo].[posRewardBalances] (
    balanceId        INT IDENTITY PRIMARY KEY,
    companyId        INT            NOT NULL,
    clientId         INT            NOT NULL,
    balance          DECIMAL(12,2)  NOT NULL DEFAULT 0,
    lifetimeEarned   DECIMAL(12,2)  NOT NULL DEFAULT 0,
    lifetimeRedeemed DECIMAL(12,2)  NOT NULL DEFAULT 0,
    lastActivity     DATETIME2      NULL
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_posRewardBalances_company_client')
    CREATE UNIQUE INDEX UQ_posRewardBalances_company_client
        ON [dbo].[posRewardBalances] (companyId, clientId);
GO

-- ── Table: posRewardTransactions (INSERT-only ledger) ───────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardTransactions')
CREATE TABLE [dbo].[posRewardTransactions] (
    transactionId   INT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    clientId        INT            NOT NULL,
    txType          NVARCHAR(20)   NOT NULL,  -- EARN | REDEEM | ADJUSTMENT | EXPIRE
    direction       NVARCHAR(1)    NOT NULL,  -- D=debit (balance down), C=credit (balance up)
    points          DECIMAL(12,2)  NOT NULL,  -- always positive; direction carries the sign
    referenceType   NVARCHAR(20)   NOT NULL,  -- ticket | redemption | manual
    referenceId     INT            NULL,      -- incomeId (ticket) / redemptionId (redemption) / NULL (manual)
    balanceAfter    DECIMAL(12,2)  NOT NULL,
    description     NVARCHAR(255)  NULL,
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT CK_posRewardTransactions_txType CHECK (txType IN ('EARN','REDEEM','ADJUSTMENT','EXPIRE')),
    CONSTRAINT CK_posRewardTransactions_direction CHECK (direction IN ('D','C')),
    CONSTRAINT CK_posRewardTransactions_referenceType CHECK (referenceType IN ('ticket','redemption','manual'))
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_posRewardTransactions_client_date')
    CREATE INDEX IX_posRewardTransactions_client_date
        ON [dbo].[posRewardTransactions] (clientId, created_At DESC);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_posRewardTransactions_reference')
    CREATE INDEX IX_posRewardTransactions_reference
        ON [dbo].[posRewardTransactions] (referenceType, referenceId);
GO
-- Idempotency: a retried earn-from-ticket call for the same (companyId, incomeId)
-- must be a no-op, never a duplicate EARN row. Filtered so redemption/manual
-- rows (referenceType<>'ticket') are unaffected.
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_posRewardTransactions_ticket')
    CREATE UNIQUE INDEX UQ_posRewardTransactions_ticket
        ON [dbo].[posRewardTransactions] (companyId, referenceId)
        WHERE referenceType = 'ticket';
GO

-- ── Table: posRewardRedemptions ─────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardRedemptions')
CREATE TABLE [dbo].[posRewardRedemptions] (
    redemptionId     INT IDENTITY PRIMARY KEY,
    companyId        INT            NOT NULL,
    clientId         INT            NOT NULL,
    catalogItemId    INT            NOT NULL,
    pointsSpent      DECIMAL(12,2)  NOT NULL,
    status           NVARCHAR(20)   NOT NULL DEFAULT 'applied',  -- applied | cancelled
    incomeId         INT            NULL,
    redeemedByUserId INT            NOT NULL,
    created_At       DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT CK_posRewardRedemptions_status CHECK (status IN ('applied','cancelled')),
    CONSTRAINT FK_posRewardRedemptions_catalogItem
        FOREIGN KEY (catalogItemId) REFERENCES [dbo].[posRewardCatalogItems](catalogItemId)
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_posRewardRedemptions_client_date')
    CREATE INDEX IX_posRewardRedemptions_client_date
        ON [dbo].[posRewardRedemptions] (clientId, created_At DESC);
GO

-- ============================================================
-- fn_posRewardStampStatus — THE stamp-card rule, used by every SP that
-- decides or shows whether a free_product reward can be redeemed
-- (redeem, sp_income_applyDiscounts, FreeProductStatus, ProductCounts,
-- sp_whatsappCustomerRewards). Per free_product catalog item of a client:
--   requiredUnits  = catalog requiredUnits; legacy rows: requiredPoints /
--                    pointsPerUnit (active rate), else requiredPoints
--   unitsPurchased = units of freeProductId bought at this company, minus the
--                    free units given in sales (one per applied redemption
--                    linked to a sale) — a free unit is not a purchase
--   unitsAvailable = unitsPurchased - applied redemptions of the item * requiredUnits
-- Cancelled redemptions consume nothing. @excludeIncomeId leaves one sale out
-- (the sale being priced: its units can't earn its own free unit).
-- Redemptions with no sale (old Rewards Dashboard) gave no unit through a
-- ticket, so they only consume requiredUnits.
-- ============================================================
IF OBJECT_ID('dbo.fn_posRewardStampStatus', 'IF') IS NOT NULL DROP FUNCTION dbo.fn_posRewardStampStatus;
GO
CREATE FUNCTION [dbo].[fn_posRewardStampStatus] (@companyId INT, @clientId INT, @excludeIncomeId INT)
RETURNS TABLE
AS
RETURN
    SELECT c.catalogItemId, c.freeProductId, c.isActive, u.requiredUnits,
           b.unitsBought - f.freeUnits AS unitsPurchased,
           b.unitsBought - f.freeUnits - r.redemptions * u.requiredUnits AS unitsAvailable
    FROM [dbo].[posRewardCatalogItems] c
    OUTER APPLY (SELECT TOP 1 pr.pointsPerUnit FROM [dbo].[posRewardProductRates] pr
                 WHERE pr.companyId = c.companyId AND pr.productId = c.freeProductId AND pr.isActive = 1) rt
    CROSS APPLY (SELECT CAST(COALESCE(c.requiredUnits,
                     CASE WHEN ISNULL(rt.pointsPerUnit, 0) > 0 THEN c.requiredPoints / rt.pointsPerUnit
                          ELSE c.requiredPoints END) AS DECIMAL(12,2)) AS requiredUnits) u
    CROSS APPLY (SELECT CAST(ISNULL(SUM(d.quantity), 0) AS DECIMAL(12,2)) AS unitsBought
                 FROM [dbo].[incomeDetails] d
                 JOIN [dbo].[income] i ON i.incomeId = d.incomeId
                 WHERE d.productId = c.freeProductId AND i.clientId = @clientId AND i.companyId = @companyId
                   AND (@excludeIncomeId IS NULL OR i.incomeId <> @excludeIncomeId)) b
    CROSS APPLY (SELECT COUNT(*) AS freeUnits
                 FROM [dbo].[posRewardRedemptions] rd
                 JOIN [dbo].[posRewardCatalogItems] fc ON fc.catalogItemId = rd.catalogItemId
                 JOIN [dbo].[income] fi ON fi.incomeId = rd.incomeId AND fi.companyId = @companyId
                 WHERE rd.companyId = @companyId AND rd.clientId = @clientId AND rd.status = 'applied'
                   AND fc.rewardType = 'free_product' AND fc.freeProductId = c.freeProductId
                   AND (@excludeIncomeId IS NULL OR rd.incomeId <> @excludeIncomeId)) f
    CROSS APPLY (SELECT COUNT(*) AS redemptions
                 FROM [dbo].[posRewardRedemptions] rd
                 WHERE rd.companyId = @companyId AND rd.clientId = @clientId
                   AND rd.catalogItemId = c.catalogItemId AND rd.status = 'applied') r
    WHERE c.companyId = @companyId AND c.rewardType = 'free_product' AND c.freeProductId IS NOT NULL;
GO

-- ============================================================
-- sp_posRewardBalances_applyDelta — internal helper, not routed.
-- Upserts a client's balance inside the CALLER's transaction (no
-- BEGIN/COMMIT here) so earn/adjust/redeem stay atomic with their
-- ledger insert. Never called directly from a route.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardBalances_applyDelta', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardBalances_applyDelta;
GO
CREATE PROCEDURE [dbo].[sp_posRewardBalances_applyDelta]
    @companyId INT, @clientId INT,
    @pointsDelta DECIMAL(12,2),
    @earnedDelta DECIMAL(12,2) = 0,
    @redeemedDelta DECIMAL(12,2) = 0,
    @newBalance DECIMAL(12,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    MERGE [dbo].[posRewardBalances] AS tgt
    USING (SELECT @companyId AS companyId, @clientId AS clientId) AS src
        ON tgt.companyId = src.companyId AND tgt.clientId = src.clientId
    WHEN MATCHED THEN UPDATE SET
        balance = tgt.balance + @pointsDelta,
        lifetimeEarned = tgt.lifetimeEarned + @earnedDelta,
        lifetimeRedeemed = tgt.lifetimeRedeemed + @redeemedDelta,
        lastActivity = GETUTCDATE()
    WHEN NOT MATCHED THEN
        INSERT (companyId, clientId, balance, lifetimeEarned, lifetimeRedeemed, lastActivity)
        VALUES (@companyId, @clientId, @pointsDelta, @earnedDelta, @redeemedDelta, GETUTCDATE());

    SELECT @newBalance = balance FROM [dbo].[posRewardBalances]
    WHERE companyId = @companyId AND clientId = @clientId;
END
GO

-- ============================================================
-- sp_posRewardProductRates — action 0=read, 1=upsert (insert-or-
-- update on (companyId, productId), never a duplicate rate row).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardProductRates', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardProductRates;
GO
CREATE PROCEDURE [dbo].[sp_posRewardProductRates]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].action'));
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].companyId'));

    BEGIN TRY
        IF @action = 1
        BEGIN
            DECLARE @productId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].productId'));
            DECLARE @pointsPerUnit DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].pointsPerUnit'));
            DECLARE @isActive BIT = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].isActive'));

            IF @companyId IS NULL OR @productId IS NULL OR @pointsPerUnit IS NULL
                RAISERROR('companyId, productId y pointsPerUnit son requeridos.', 16, 1);

            MERGE [dbo].[posRewardProductRates] AS tgt
            USING (SELECT @companyId AS companyId, @productId AS productId) AS src
                ON tgt.companyId = src.companyId AND tgt.productId = src.productId
            WHEN MATCHED THEN UPDATE SET
                pointsPerUnit = @pointsPerUnit,
                isActive = ISNULL(@isActive, tgt.isActive),
                updated_at = GETUTCDATE()
            WHEN NOT MATCHED THEN
                INSERT (companyId, productId, pointsPerUnit, isActive)
                VALUES (@companyId, @productId, @pointsPerUnit, ISNULL(@isActive, 1));

            DECLARE @rateId INT = (SELECT rateId FROM [dbo].[posRewardProductRates] WHERE companyId=@companyId AND productId=@productId);
            SELECT ('{"result":[{"value":' + CAST(@rateId AS NVARCHAR(20)) + ',"msg":"Upserted Successfully","error":"0"}]}') AS [jsonResult]
        END
        ELSE IF @action IN (2,3)
            RAISERROR('Use action=1 (upsert) for posRewardProductRates.', 16, 1);
        ELSE
        BEGIN
            -- action 0 / read
            DECLARE @productIdFilter INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].productId'));

            DECLARE @ratesJson NVARCHAR(MAX) = (
                SELECT rateId, companyId, productId, pointsPerUnit, isActive
                FROM [dbo].[posRewardProductRates]
                WHERE companyId = @companyId
                  AND (@productIdFilter IS NULL OR productId = @productIdFilter)
                ORDER BY productId
                FOR JSON PATH
            );
            SELECT ('{"result":[{"posRewardProductRates":' + ISNULL(@ratesJson, '[]') + '}]}') AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardCatalogItems — action 0=read, 1=insert, 2=update, 3=delete.
-- Simple CRUD — no immutability constraint (unlike posRewardTransactions).
-- The single table for every discount (2026-10-16): coupons (coupon_b2g1 +
-- code/dates/firstPurchaseOnly), points rewards (discount_*) and stamp cards
-- (free_product + requiredUnits). Read hides coupons unless includeCoupons=1.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardCatalogItems', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardCatalogItems;
GO
CREATE PROCEDURE [dbo].[sp_posRewardCatalogItems]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].action'));
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].companyId'));

    BEGIN TRY
        IF @action = 1
        BEGIN
            DECLARE @name NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].name');
            DECLARE @rewardType NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].rewardType');
            DECLARE @requiredPoints DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].requiredPoints'));
            DECLARE @discountValue DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].discountValue'));
            DECLARE @freeProductId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].freeProductId'));
            DECLARE @isActive BIT = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].isActive'));
            DECLARE @description NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].description');
            DECLARE @code VARCHAR(30) = NULLIF(UPPER(LTRIM(RTRIM(JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].code')))), '');
            DECLARE @startAtUtc DATETIME2(0) = TRY_CONVERT(DATETIME2(0), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].startAtUtc'));
            DECLARE @endAtUtc DATETIME2(0) = TRY_CONVERT(DATETIME2(0), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].endAtUtc'));
            DECLARE @firstPurchaseOnly BIT = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].firstPurchaseOnly')), 0);
            DECLARE @requiredUnits DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].requiredUnits'));

            -- Coupons cost no points; stamp cards sent with only requiredUnits
            -- keep requiredPoints in step for fronts that still read it.
            IF @rewardType = 'coupon_b2g1' SET @requiredPoints = ISNULL(@requiredPoints, 0);
            IF @rewardType = 'free_product' SET @requiredPoints = ISNULL(@requiredPoints, @requiredUnits);
            IF @rewardType = 'free_product' SET @requiredUnits = ISNULL(@requiredUnits, @requiredPoints);

            IF @companyId IS NULL OR @name IS NULL OR @rewardType IS NULL OR @requiredPoints IS NULL
                RAISERROR('companyId, name, rewardType y requiredPoints son requeridos.', 16, 1);

            INSERT INTO [dbo].[posRewardCatalogItems]
                (companyId, name, rewardType, requiredPoints, discountValue, freeProductId, isActive, description,
                 code, startAtUtc, endAtUtc, firstPurchaseOnly, requiredUnits)
            VALUES
                (@companyId, @name, @rewardType, @requiredPoints, @discountValue, @freeProductId, ISNULL(@isActive,1), @description,
                 @code, @startAtUtc, @endAtUtc, @firstPurchaseOnly, @requiredUnits);

            DECLARE @newId INT = SCOPE_IDENTITY();
            SELECT ('{"result":[{"value":' + CAST(@newId AS NVARCHAR(20)) + ',"msg":"Inserted Successfully","error":"0"}]}') AS [jsonResult]
        END
        ELSE IF @action = 2
        BEGIN
            DECLARE @catalogItemId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].catalogItemId'));
            IF @catalogItemId IS NULL RAISERROR('catalogItemId es requerido.', 16, 1);

            -- Columns added 2026-10-16 change only when their key is sent, so a
            -- POS build that doesn't know them can't wipe a coupon's code.
            DECLARE @keys TABLE ([key] NVARCHAR(100));
            INSERT INTO @keys SELECT [key] FROM OPENJSON(@pjsonfile, '$.posRewardCatalogItems[0]');

            UPDATE [dbo].[posRewardCatalogItems] SET
                name           = ISNULL(JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].name'), name),
                rewardType     = ISNULL(JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].rewardType'), rewardType),
                requiredPoints = ISNULL(TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].requiredPoints')), requiredPoints),
                discountValue  = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].discountValue')),
                freeProductId  = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].freeProductId')),
                isActive       = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].isActive')), isActive),
                description    = JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].description'),
                code           = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'code')
                                      THEN NULLIF(UPPER(LTRIM(RTRIM(JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].code')))), '') ELSE code END,
                startAtUtc     = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'startAtUtc')
                                      THEN TRY_CONVERT(DATETIME2(0), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].startAtUtc')) ELSE startAtUtc END,
                endAtUtc       = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'endAtUtc')
                                      THEN TRY_CONVERT(DATETIME2(0), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].endAtUtc')) ELSE endAtUtc END,
                firstPurchaseOnly = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'firstPurchaseOnly')
                                      THEN ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].firstPurchaseOnly')), 0) ELSE firstPurchaseOnly END,
                requiredUnits  = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'requiredUnits')
                                      THEN TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].requiredUnits')) ELSE requiredUnits END,
                updated_at     = GETUTCDATE()
            WHERE catalogItemId = @catalogItemId AND companyId = @companyId;

            SELECT ('{"result":[{"value":' + CAST(@catalogItemId AS NVARCHAR(20)) + ',"msg":"Updated Successfully","error":"0"}]}') AS [jsonResult]
        END
        ELSE IF @action = 3
        BEGIN
            DECLARE @deleteId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].catalogItemId'));
            IF @deleteId IS NULL RAISERROR('catalogItemId es requerido.', 16, 1);

            DELETE FROM [dbo].[posRewardCatalogItems] WHERE catalogItemId = @deleteId AND companyId = @companyId;
            SELECT ('{"result":[{"value":' + CAST(@deleteId AS NVARCHAR(20)) + ',"msg":"Deleted Successfully","error":"0"}]}') AS [jsonResult]
        END
        ELSE
        BEGIN
            -- action 0 / read
            DECLARE @activeOnly BIT = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].activeOnly'));
            -- Coupons (coupon_b2g1) are listed only on request: the rewards
            -- screens, menuLaundy and the sale message list what a client can
            -- redeem, and a coupon is typed at checkout instead.
            DECLARE @includeCoupons BIT = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].includeCoupons')), 0);
            -- With clientId, first-purchase coupons are left out once that client
            -- has a sale at this company (the rule sp_income_applyDiscounts applies).
            DECLARE @forClientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].clientId'));
            DECLARE @clientHasSale BIT = CASE WHEN @forClientId IS NOT NULL AND EXISTS (
                SELECT 1 FROM [dbo].[income] WHERE companyId = @companyId AND clientId = @forClientId) THEN 1 ELSE 0 END;
            DECLARE @itemsJson NVARCHAR(MAX) = (
                SELECT catalogItemId, companyId, name, rewardType, requiredPoints,
                       discountValue, freeProductId, isActive, description,
                       code, CONVERT(NVARCHAR(19), startAtUtc, 126) AS startAtUtc,
                       CONVERT(NVARCHAR(19), endAtUtc, 126) AS endAtUtc, firstPurchaseOnly, requiredUnits
                FROM [dbo].[posRewardCatalogItems]
                WHERE companyId = @companyId
                  AND (@activeOnly IS NULL OR @activeOnly = 0 OR isActive = 1)
                  AND (@includeCoupons = 1 OR rewardType <> 'coupon_b2g1')
                  AND NOT (rewardType = 'coupon_b2g1' AND firstPurchaseOnly = 1 AND @clientHasSale = 1)
                ORDER BY requiredPoints
                FOR JSON PATH
            );
            SELECT ('{"result":[{"posRewardCatalogItems":' + ISNULL(@itemsJson, '[]') + '}]}') AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardBalances — action 0/read ONLY (public). Writes happen
-- exclusively inside sp_posRewardTransactions_earnFromTicket/_adjust
-- and sp_posRewardRedemptions_redeem via sp_posRewardBalances_applyDelta.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardBalances', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardBalances;
GO
CREATE PROCEDURE [dbo].[sp_posRewardBalances]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].companyId'));
        DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].clientId'));
        IF @companyId IS NULL RAISERROR('companyId es requerido.', 16, 1);

        DECLARE @balancesJson NVARCHAR(MAX) = (
            SELECT companyId, clientId, balance, lifetimeEarned, lifetimeRedeemed,
                   CONVERT(NVARCHAR, lastActivity, 127) AS lastActivity
            FROM [dbo].[posRewardBalances]
            WHERE companyId = @companyId
              AND (@clientId IS NULL OR clientId = @clientId)
            ORDER BY balance DESC
            FOR JSON PATH
        );
        SELECT ('{"result":[{"posRewardBalances":' + ISNULL(@balancesJson, '[]') + '}]}') AS [jsonResult]
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardBalances_dashboardSummary — read-only, cross-table.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardBalances_dashboardSummary', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardBalances_dashboardSummary;
GO
CREATE PROCEDURE [dbo].[sp_posRewardBalances_dashboardSummary]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].companyId'));
    DECLARE @startDate DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].startDate'));
    DECLARE @endDate DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].endDate'));

    DECLARE @pointsIssued DECIMAL(14,2), @pointsRedeemed DECIMAL(14,2);
    SELECT
        @pointsIssued = ISNULL(SUM(CASE WHEN direction = 'C' THEN points ELSE 0 END), 0),
        @pointsRedeemed = ISNULL(SUM(CASE WHEN direction = 'D' THEN points ELSE 0 END), 0)
    FROM [dbo].[posRewardTransactions]
    WHERE companyId = @companyId
      AND (@startDate IS NULL OR CONVERT(DATE, created_At) >= @startDate)
      AND (@endDate IS NULL OR CONVERT(DATE, created_At) <= @endDate);

    DECLARE @redemptionsCount INT = (
        SELECT COUNT(*) FROM [dbo].[posRewardRedemptions]
        WHERE companyId = @companyId AND status = 'applied'
          AND (@startDate IS NULL OR CONVERT(DATE, created_At) >= @startDate)
          AND (@endDate IS NULL OR CONVERT(DATE, created_At) <= @endDate)
    );

    DECLARE @topCustomersJson NVARCHAR(MAX) = (
        SELECT TOP 10 clientId, balance, lifetimeEarned
        FROM [dbo].[posRewardBalances]
        WHERE companyId = @companyId
        ORDER BY lifetimeEarned DESC
        FOR JSON PATH
    );

    DECLARE @activityJson NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR, CONVERT(DATE, created_At), 23) AS [date],
               SUM(CASE WHEN direction = 'C' THEN points ELSE 0 END) AS earned,
               SUM(CASE WHEN direction = 'D' THEN points ELSE 0 END) AS redeemed
        FROM [dbo].[posRewardTransactions]
        WHERE companyId = @companyId
          AND (@startDate IS NULL OR CONVERT(DATE, created_At) >= @startDate)
          AND (@endDate IS NULL OR CONVERT(DATE, created_At) <= @endDate)
        GROUP BY CONVERT(DATE, created_At)
        ORDER BY CONVERT(DATE, created_At)
        FOR JSON PATH
    );

    SELECT
        @pointsIssued AS pointsIssued,
        @pointsRedeemed AS pointsRedeemed,
        @redemptionsCount AS redemptionsCount,
        ISNULL(@topCustomersJson, '[]') AS topCustomersJson,
        ISNULL(@activityJson, '[]') AS activityJson
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
END
GO

-- ============================================================
-- sp_posRewardTransactions — action 0=read, 1=generic ledger insert
-- (e.g. future EXPIRE entries); 2/3 always rejected (INSERT-only ledger).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardTransactions', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardTransactions;
GO
CREATE PROCEDURE [dbo].[sp_posRewardTransactions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].action'));
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].companyId'));

    BEGIN TRY
        IF @action IN (2,3)
            RAISERROR('posRewardTransactions es un ledger INSERT-only. Usa una nueva entrada ADJUSTMENT/EXPIRE en su lugar.', 16, 1);
        ELSE IF @action = 1
        BEGIN
            RAISERROR('Usa sp_posRewardTransactions_earnFromTicket o _adjust para insertar en el ledger.', 16, 1);
        END
        ELSE
        BEGIN
            -- action 0 / read
            DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].clientId'));
            DECLARE @txType NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].txType');

            DECLARE @txJson NVARCHAR(MAX) = (
                SELECT transactionId, companyId, clientId, txType, direction, points,
                       referenceType, referenceId, balanceAfter, description,
                       CONVERT(NVARCHAR, created_At, 127) AS created_At
                FROM [dbo].[posRewardTransactions]
                WHERE companyId = @companyId
                  AND (@clientId IS NULL OR clientId = @clientId)
                  AND (@txType IS NULL OR txType = @txType)
                ORDER BY created_At DESC
                FOR JSON PATH
            );
            SELECT ('{"result":[{"posRewardTransactions":' + ISNULL(@txJson, '[]') + '}]}') AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardTransactions_earnFromTicket — the ONLY path allowed to
-- insert EARN rows. Idempotent per (companyId, incomeId): a retried
-- call for an already-posted ticket returns the existing result
-- instead of erroring or double-posting (UQ_posRewardTransactions_ticket
-- would otherwise raise a duplicate-key error under a race).
-- Points: companies with posRewardSettings.earnPct earn that % of the net
-- paid on eligible lines (incomeDetails.netAmount); the rest earn
-- pointsPerUnit * units. Either way only products with an active rate earn,
-- and free units earn nothing. Needs migration 2026-10-18b.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardTransactions_earnFromTicket', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardTransactions_earnFromTicket;
GO
CREATE PROCEDURE [dbo].[sp_posRewardTransactions_earnFromTicket]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].companyId'));
        DECLARE @incomeId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].incomeId'));

        IF @companyId IS NULL OR @incomeId IS NULL
            RAISERROR('companyId e incomeId son requeridos.', 16, 1);

        DECLARE @clientId INT = (SELECT clientId FROM [dbo].[income] WHERE incomeId = @incomeId AND companyId = @companyId);
        IF @clientId IS NULL
            RAISERROR('El ticket no existe para esta empresa.', 16, 1);

        -- clientId = 1 is the walk-in/"mostrador" placeholder CartPage.tsx
        -- sends when no real client was scanned/selected (dbo.income.clientId
        -- is NOT NULL, so the ticket itself still needs SOME value there).
        -- Same no-op shape as "no rated products" below -- a successful
        -- response, not an error -- so anonymous counter sales don't
        -- silently accrue points onto whichever real client holds id 1.
        IF @clientId = 1
        BEGIN
            DECLARE @walkInBalance DECIMAL(12,2) = ISNULL(
                (SELECT balance FROM [dbo].[posRewardBalances] WHERE companyId = @companyId AND clientId = @clientId), 0);
            SELECT CAST(0 AS DECIMAL(12,2)) AS pointsEarned, @walkInBalance AS newBalance, CAST(NULL AS INT) AS transactionId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            RETURN;
        END

        -- Idempotent replay: same ticket already posted -> return that result, no new row.
        DECLARE @existingTxId INT, @existingPoints DECIMAL(12,2), @existingBalance DECIMAL(12,2);
        SELECT TOP 1 @existingTxId = transactionId, @existingPoints = points, @existingBalance = balanceAfter
        FROM [dbo].[posRewardTransactions]
        WHERE companyId = @companyId AND referenceType = 'ticket' AND referenceId = @incomeId;

        IF @existingTxId IS NOT NULL
        BEGIN
            SELECT @existingPoints AS pointsEarned, @existingBalance AS newBalance, @existingTxId AS transactionId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            RETURN;
        END

        -- Server-side calculation ONLY: never trust points from the frontend.
        -- A product earns only if it has an active posRewardProductRates row.
        DECLARE @earnPct DECIMAL(5,2) = (SELECT earnPct FROM [dbo].[posRewardSettings] WHERE companyId = @companyId);
        DECLARE @points DECIMAL(12,2);
        IF @earnPct IS NOT NULL
        BEGIN
            -- % of the net paid on eligible lines (GMO Lavandería: 2.5%, 1 pt = $1).
            -- netAmount is written by sp_income_applyDiscounts when the sale had
            -- a discount; otherwise income.total is split by line price (option
            -- prices), or by quantity when the lines have no option prices.
            DECLARE @saleTotal DECIMAL(12,2) = (SELECT total FROM [dbo].[income] WHERE incomeId = @incomeId);
            DECLARE @lines TABLE (productId INT, qty INT, price DECIMAL(12,2), netAmount DECIMAL(12,2));
            INSERT INTO @lines (productId, qty, price, netAmount)
            SELECT d.productId, ISNULL(d.quantity, 1),
                   ISNULL((SELECT SUM(CAST(c.price AS DECIMAL(10,2)) * ISNULL(ido.quantity, 1))
                           FROM [dbo].[incomeDetailOptions] ido
                           JOIN [dbo].[productOptionChoices] c ON c.productOptionChoiceId = ido.productOptionChoiceId
                           WHERE ido.incomeDetailId = d.incomeDetailId), 0),
                   d.netAmount
            FROM [dbo].[incomeDetails] d
            WHERE d.incomeId = @incomeId;
            DECLARE @sumPrice DECIMAL(12,2) = (SELECT SUM(price) FROM @lines);
            DECLARE @sumQty INT = (SELECT SUM(qty) FROM @lines);

            SET @points = ROUND((
                SELECT SUM(COALESCE(l.netAmount,
                                    CASE WHEN @sumPrice > 0 THEN @saleTotal * l.price / @sumPrice
                                         ELSE @saleTotal * l.qty / NULLIF(@sumQty, 0) END))
                FROM @lines l
                WHERE EXISTS (SELECT 1 FROM [dbo].[posRewardProductRates] r
                              WHERE r.productId = l.productId AND r.companyId = @companyId AND r.isActive = 1)
            ) * @earnPct / 100, 2);
        END
        ELSE
            -- Points per unit. Free units (a stamp-card reward redeemed in this
            -- sale) earn nothing.
            SET @points = (
                SELECT SUM(r.pointsPerUnit * CASE WHEN p.qty > p.freeUnits THEN p.qty - p.freeUnits ELSE 0 END)
                FROM (
                    SELECT d.productId, SUM(d.quantity) AS qty,
                           (SELECT COUNT(*) FROM [dbo].[posRewardRedemptions] rd
                            JOIN [dbo].[posRewardCatalogItems] c ON c.catalogItemId = rd.catalogItemId
                            WHERE rd.incomeId = @incomeId AND rd.status = 'applied'
                              AND c.rewardType = 'free_product' AND c.freeProductId = d.productId) AS freeUnits
                    FROM [dbo].[incomeDetails] d
                    WHERE d.incomeId = @incomeId
                    GROUP BY d.productId
                ) p
                JOIN [dbo].[posRewardProductRates] r
                    ON r.productId = p.productId AND r.companyId = @companyId AND r.isActive = 1
            );

        IF @points IS NULL OR @points <= 0
        BEGIN
            -- No rated products on this ticket -- nothing to post, but a
            -- successful no-op response (not a 404/500) so the POS never
            -- treats "no configured rate yet" as a failure.
            DECLARE @currentBalance DECIMAL(12,2) = ISNULL(
                (SELECT balance FROM [dbo].[posRewardBalances] WHERE companyId = @companyId AND clientId = @clientId), 0);
            SELECT CAST(0 AS DECIMAL(12,2)) AS pointsEarned, @currentBalance AS newBalance, CAST(NULL AS INT) AS transactionId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            RETURN;
        END

        BEGIN TRAN;

        DECLARE @newBalance DECIMAL(12,2);
        EXEC [dbo].[sp_posRewardBalances_applyDelta]
            @companyId = @companyId, @clientId = @clientId,
            @pointsDelta = @points, @earnedDelta = @points, @redeemedDelta = 0,
            @newBalance = @newBalance OUTPUT;

        INSERT INTO [dbo].[posRewardTransactions]
            (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
        VALUES
            (@companyId, @clientId, 'EARN', 'C', @points, 'ticket', @incomeId, @newBalance, CONCAT('Ticket #', @incomeId));

        DECLARE @transactionId INT = SCOPE_IDENTITY();

        COMMIT TRAN;

        SELECT @points AS pointsEarned, @newBalance AS newBalance, @transactionId AS transactionId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        -- Race: two concurrent retries for the same ticket both pass the
        -- idempotency SELECT before either commits -> UNIQUE violation here
        -- is expected and not a real error; surface it distinctly.
        IF ERROR_NUMBER() IN (2601, 2627) AND @Error LIKE '%UQ_posRewardTransactions_ticket%'
            SELECT ('{"error":"already_posted"}') AS [jsonResult]
        ELSE
            SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardTransactions_adjust — manual admin points adjustment.
-- points may be positive or negative.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardTransactions_adjust', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardTransactions_adjust;
GO
CREATE PROCEDURE [dbo].[sp_posRewardTransactions_adjust]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].companyId'));
        DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].clientId'));
        DECLARE @points DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].points'));
        DECLARE @description NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].description');
        DECLARE @createdByUserId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].createdByUserId'));

        IF @companyId IS NULL OR @clientId IS NULL OR @points IS NULL OR @points = 0
            RAISERROR('companyId, clientId y points (distinto de 0) son requeridos.', 16, 1);

        DECLARE @direction NVARCHAR(1) = CASE WHEN @points >= 0 THEN 'C' ELSE 'D' END;
        DECLARE @absPoints DECIMAL(12,2) = ABS(@points);
        -- EXEC's @param = value only accepts a constant or a bare variable,
        -- never an inline expression -- CASE has to be pre-computed here.
        DECLARE @earnedDelta DECIMAL(12,2) = CASE WHEN @points > 0 THEN @points ELSE 0 END;
        DECLARE @redeemedDeltaIn DECIMAL(12,2) = CASE WHEN @points < 0 THEN @absPoints ELSE 0 END;

        BEGIN TRAN;

        DECLARE @newBalance DECIMAL(12,2);
        EXEC [dbo].[sp_posRewardBalances_applyDelta]
            @companyId = @companyId, @clientId = @clientId,
            @pointsDelta = @points,
            @earnedDelta = @earnedDelta,
            @redeemedDelta = @redeemedDeltaIn,
            @newBalance = @newBalance OUTPUT;

        INSERT INTO [dbo].[posRewardTransactions]
            (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
        VALUES
            (@companyId, @clientId, 'ADJUSTMENT', @direction, @absPoints, 'manual', NULL, @newBalance,
             ISNULL(@description, CONCAT('Ajuste manual por usuario ', @createdByUserId)));

        COMMIT TRAN;

        SELECT @newBalance AS newBalance
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardRedemptions — action 0=read only (writes go through
-- sp_posRewardRedemptions_redeem, which is transactional).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardRedemptions', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardRedemptions;
GO
CREATE PROCEDURE [dbo].[sp_posRewardRedemptions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].companyId'));
        DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].clientId'));
        IF @companyId IS NULL RAISERROR('companyId es requerido.', 16, 1);

        DECLARE @redemptionsJson NVARCHAR(MAX) = (
            SELECT redemptionId, companyId, clientId, catalogItemId, pointsSpent, status,
                   incomeId, redeemedByUserId, CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM [dbo].[posRewardRedemptions]
            WHERE companyId = @companyId
              AND (@clientId IS NULL OR clientId = @clientId)
            ORDER BY created_At DESC
            FOR JSON PATH
        );
        SELECT ('{"result":[{"posRewardRedemptions":' + ISNULL(@redemptionsJson, '[]') + '}]}') AS [jsonResult]
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardRedemptions_redeem — transactional: insufficient balance
-- rolls back and returns {"error":"insufficient_points","balance"} —
-- a valid business outcome, NOT an exception (Python maps it to HTTP 200).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardRedemptions_redeem', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardRedemptions_redeem;
GO
CREATE PROCEDURE [dbo].[sp_posRewardRedemptions_redeem]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].companyId'));
        DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].clientId'));
        DECLARE @catalogItemId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].catalogItemId'));
        DECLARE @redeemedByUserId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].redeemedByUserId'));
        DECLARE @incomeId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].incomeId'));

        IF @companyId IS NULL OR @clientId IS NULL OR @catalogItemId IS NULL OR @redeemedByUserId IS NULL
            RAISERROR('companyId, clientId, catalogItemId y redeemedByUserId son requeridos.', 16, 1);

        DECLARE @requiredPoints DECIMAL(12,2), @rewardType NVARCHAR(30), @freeProductId INT;
        SELECT @requiredPoints = requiredPoints, @rewardType = rewardType, @freeProductId = freeProductId
        FROM [dbo].[posRewardCatalogItems]
        WHERE catalogItemId = @catalogItemId AND companyId = @companyId AND isActive = 1;

        IF @requiredPoints IS NULL
            RAISERROR('La recompensa no existe, no pertenece a esta empresa, o no está activa.', 16, 1);
        IF @rewardType = 'coupon_b2g1'
            RAISERROR('Los cupones se aplican con la venta (promotionCode), no se canjean.', 16, 1);

        DECLARE @isFreeProduct BIT = CASE WHEN @rewardType = 'free_product' AND @freeProductId IS NOT NULL THEN 1 ELSE 0 END;

        -- Check and consume under one per-client lock, so two concurrent
        -- redemptions (or a redemption and a sale) can't spend the same points
        -- or stamps. sp_income_applyDiscounts takes the same lock.
        BEGIN TRAN;
        DECLARE @lockName NVARCHAR(255) = CONCAT(N'posRewards:', @companyId, N':', @clientId);
        EXEC sp_getapplock @Resource = @lockName, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;

        -- free_product rewards are earned from THAT product's purchases
        -- (fn_posRewardStampStatus), never from the points balance.
        IF @isFreeProduct = 1
        BEGIN
            DECLARE @requiredUnits DECIMAL(12,2), @unitsPurchased DECIMAL(12,2), @unitsAvailable DECIMAL(12,2);
            SELECT @requiredUnits = requiredUnits, @unitsPurchased = unitsPurchased, @unitsAvailable = unitsAvailable
            FROM [dbo].[fn_posRewardStampStatus](@companyId, @clientId, @incomeId)
            WHERE catalogItemId = @catalogItemId;

            IF ISNULL(@unitsAvailable, 0) < ISNULL(@requiredUnits, 0) OR @requiredUnits IS NULL
            BEGIN
                ROLLBACK TRAN;
                SELECT ('{"error":"insufficient_product_units","required":' + CONVERT(NVARCHAR(30), ISNULL(@requiredUnits, 0)) +
                    ',"purchased":' + CONVERT(NVARCHAR(30), ISNULL(@unitsPurchased, 0)) +
                    ',"available":' + CONVERT(NVARCHAR(30), ISNULL(@unitsAvailable, 0)) + '}') AS [jsonResult]
                RETURN;
            END
        END

        DECLARE @currentBalance DECIMAL(12,2) = ISNULL(
            (SELECT balance FROM [dbo].[posRewardBalances] WITH (UPDLOCK)
             WHERE companyId = @companyId AND clientId = @clientId), 0);

        IF @isFreeProduct = 0 AND @currentBalance < @requiredPoints
        BEGIN
            ROLLBACK TRAN;
            SELECT ('{"error":"insufficient_points","balance":' + CONVERT(NVARCHAR(30), @currentBalance) + '}') AS [jsonResult]
            RETURN;
        END

        DECLARE @pointsSpent DECIMAL(12,2) = CASE WHEN @isFreeProduct = 1 THEN 0 ELSE @requiredPoints END;

        INSERT INTO [dbo].[posRewardRedemptions]
            (companyId, clientId, catalogItemId, pointsSpent, status, incomeId, redeemedByUserId)
        VALUES
            (@companyId, @clientId, @catalogItemId, @pointsSpent, 'applied', @incomeId, @redeemedByUserId);

        DECLARE @redemptionId INT = SCOPE_IDENTITY();
        DECLARE @newBalance DECIMAL(12,2) = @currentBalance;

        IF @isFreeProduct = 0
        BEGIN
            -- EXEC's @param = value only accepts a constant or a bare variable,
            -- never an inline expression -- the negation has to be pre-computed here.
            DECLARE @negRequiredPoints DECIMAL(12,2) = -@requiredPoints;
            EXEC [dbo].[sp_posRewardBalances_applyDelta]
                @companyId = @companyId, @clientId = @clientId,
                @pointsDelta = @negRequiredPoints, @earnedDelta = 0, @redeemedDelta = @requiredPoints,
                @newBalance = @newBalance OUTPUT;

            INSERT INTO [dbo].[posRewardTransactions]
                (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
            VALUES
                (@companyId, @clientId, 'REDEEM', 'D', @requiredPoints, 'redemption', @redemptionId, @newBalance,
                 CONCAT('Canje #', @redemptionId));
        END

        COMMIT TRAN;

        SELECT 'applied' AS status, @redemptionId AS redemptionId, @pointsSpent AS pointsSpent, @newBalance AS newBalance
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- sp_posRewardProductCounts
-- Returns available units per stamp-card product for a client
-- (fn_posRewardStampStatus): purchased (free units excluded) - consumed.
-- Used by the stamp-card UI to show accurate per-product progress.
-- Input:  { "posRewardProductCounts": [{ "companyId": int, "clientId": int }] }
-- Output: { "result": [{ "posRewardProductCounts": [{ "productId", "unitsPurchased", "unitsConsumed", "unitsAvailable" }] }] }
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.sp_posRewardProductCounts', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardProductCounts;
GO
CREATE PROCEDURE [dbo].[sp_posRewardProductCounts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductCounts[0].companyId'));
        DECLARE @clientId  INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductCounts[0].clientId'));

        IF @companyId IS NULL OR @clientId IS NULL
        BEGIN
            SELECT ('{"error":"companyId and clientId are required"}') AS [jsonResult];
            RETURN;
        END

        -- Same rule as redeem / checkout (fn_posRewardStampStatus): purchases
        -- at this company, free units excluded, applied redemptions consumed.
        -- One row per stamp-card product (items of the same product add up).
        SELECT (
            SELECT st.freeProductId AS productId,
                   MAX(st.unitsPurchased) AS unitsPurchased,
                   SUM(st.unitsPurchased - st.unitsAvailable) AS unitsConsumed,
                   MAX(st.unitsPurchased) - SUM(st.unitsPurchased - st.unitsAvailable) AS unitsAvailable
            FROM [dbo].[fn_posRewardStampStatus](@companyId, @clientId, NULL) st
            GROUP BY st.freeProductId
            FOR JSON PATH, ROOT('posRewardProductCounts')
        ) AS [jsonResult];

    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardRedemptions_reverseForIncome — a deleted sale gives back the
-- reward it used: its applied redemptions become 'cancelled' (the stamp-card
-- units count again, fn_posRewardStampStatus ignores cancelled rows) and any
-- points spent are credited back with an ADJUSTMENT/C row pointing at the
-- redemption. Nothing is deleted. Idempotent: only 'applied' rows change.
-- Called by modules/income.py after sp_income action 2, BEFORE
-- sp_income_reverseOnDelete (so taking back the sale's earned points sees
-- the refunded balance). Refuses while the sale still exists.
-- Input:  @incomeId INT
-- Output: one row (redemptionsCancelled, pointsRefunded)
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardRedemptions_reverseForIncome', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardRedemptions_reverseForIncome;
GO
CREATE PROCEDURE [dbo].[sp_posRewardRedemptions_reverseForIncome]
    @incomeId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM [dbo].[income] WHERE incomeId = @incomeId)
    BEGIN
        RAISERROR('La venta todavía existe; solo se revierten canjes de ventas eliminadas.', 16, 1);
        RETURN;
    END

    DECLARE @cancelled INT = 0, @refunded DECIMAL(12,2) = 0;
    DECLARE @rid INT, @companyId INT, @clientId INT, @points DECIMAL(12,2), @newBalance DECIMAL(12,2);

    BEGIN TRY
        BEGIN TRAN;
        DECLARE reds CURSOR LOCAL FAST_FORWARD FOR
            SELECT redemptionId, companyId, clientId, pointsSpent
            FROM [dbo].[posRewardRedemptions]
            WHERE incomeId = @incomeId AND status = 'applied';
        OPEN reds;
        FETCH NEXT FROM reds INTO @rid, @companyId, @clientId, @points;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @lockName NVARCHAR(255) = CONCAT(N'posRewards:', @companyId, N':', @clientId);
            EXEC sp_getapplock @Resource = @lockName, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;

            UPDATE [dbo].[posRewardRedemptions] SET status = 'cancelled'
            WHERE redemptionId = @rid AND status = 'applied';
            SET @cancelled += 1;

            IF @points > 0
            BEGIN
                DECLARE @negPoints DECIMAL(12,2) = -@points;
                EXEC [dbo].[sp_posRewardBalances_applyDelta]
                    @companyId = @companyId, @clientId = @clientId,
                    @pointsDelta = @points, @earnedDelta = 0, @redeemedDelta = @negPoints,
                    @newBalance = @newBalance OUTPUT;
                INSERT INTO [dbo].[posRewardTransactions]
                    (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
                VALUES (@companyId, @clientId, 'ADJUSTMENT', 'C', @points, 'redemption', @rid, @newBalance,
                        CONCAT('Reversa canje #', @rid, ' (venta #', @incomeId, ' eliminada)'));
                SET @refunded += @points;
            END
            FETCH NEXT FROM reds INTO @rid, @companyId, @clientId, @points;
        END
        CLOSE reds;
        DEALLOCATE reds;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH

    SELECT @cancelled AS redemptionsCancelled, @refunded AS pointsRefunded;
END
GO
