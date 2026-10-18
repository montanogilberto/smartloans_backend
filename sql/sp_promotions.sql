-- ============================================================
-- Promotions = the coupons in dbo.posRewardCatalogItems (rewardType
-- 'coupon_b2g1'), the single table for every discount since 2026-10-16
-- (docs/promotions_rewards_analysis.md). The POS applies them at checkout
-- through sp_income_applyDiscounts; the WhatsApp assistant lists action 0
-- with activeOnly=1.
-- Response shape unchanged from the old dbo.promotions version, so the agent
-- (get_promotions) keeps working: promotionId is now the catalogItemId and
-- promoType is always 'B2G1'. Also returns productId (NULL = every product)
-- and firstPurchaseOnly.
--   action 0 list · 1 insert · 2 update (only keys sent) · 3 deactivate
-- ============================================================

IF OBJECT_ID('dbo.sp_promotions', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_promotions;
GO
CREATE PROCEDURE [dbo].[sp_promotions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action            INT           = TRY_CONVERT(INT,       JSON_VALUE(@pjsonfile, '$.promotions[0].action'));
        DECLARE @companyId         INT           = TRY_CONVERT(INT,       JSON_VALUE(@pjsonfile, '$.promotions[0].companyId'));
        DECLARE @promotionId       INT           = TRY_CONVERT(INT,       JSON_VALUE(@pjsonfile, '$.promotions[0].promotionId'));
        DECLARE @code              VARCHAR(30)   = UPPER(LTRIM(RTRIM(     JSON_VALUE(@pjsonfile, '$.promotions[0].code'))));
        DECLARE @name              NVARCHAR(120) =                        JSON_VALUE(@pjsonfile, '$.promotions[0].name');
        DECLARE @promoType         VARCHAR(20)   = UPPER(               JSON_VALUE(@pjsonfile, '$.promotions[0].promoType'));
        DECLARE @description       NVARCHAR(255) =                        JSON_VALUE(@pjsonfile, '$.promotions[0].description');
        DECLARE @startAtUtc        DATETIME2(0)  = TRY_CONVERT(DATETIME2(0), JSON_VALUE(@pjsonfile, '$.promotions[0].startAtUtc'));
        DECLARE @endAtUtc          DATETIME2(0)  = TRY_CONVERT(DATETIME2(0), JSON_VALUE(@pjsonfile, '$.promotions[0].endAtUtc'));
        DECLARE @isActive          BIT           = TRY_CONVERT(BIT,       JSON_VALUE(@pjsonfile, '$.promotions[0].isActive'));
        DECLARE @productId         INT           = TRY_CONVERT(INT,       JSON_VALUE(@pjsonfile, '$.promotions[0].productId'));
        DECLARE @firstPurchaseOnly BIT           = TRY_CONVERT(BIT,       JSON_VALUE(@pjsonfile, '$.promotions[0].firstPurchaseOnly'));
        DECLARE @activeOnly        BIT           = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.promotions[0].activeOnly')), 0);
        DECLARE @nowUtc            DATETIME2     = SYSUTCDATETIME();

        -- Keys present in the payload (action 2 only changes those). OPENJSON
        -- because JSON_PATH_EXISTS needs SQL Server 2022 (DB compat is 130).
        DECLARE @keys TABLE ([key] NVARCHAR(100));
        INSERT INTO @keys SELECT [key] FROM OPENJSON(@pjsonfile, '$.promotions[0]');

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END

        IF @action IN (1, 2) AND @promoType IS NOT NULL AND @promoType <> 'B2G1'
        BEGIN
            SELECT '{"error":"promoType must be B2G1 (the only coupon the POS applies)"}' AS jsonResult;
            RETURN;
        END

        IF @action = 1
        BEGIN
            IF NULLIF(@code, '') IS NULL OR NULLIF(LTRIM(@name), '') IS NULL
            BEGIN
                SELECT '{"error":"code and name are required"}' AS jsonResult;
                RETURN;
            END
            IF EXISTS (SELECT 1 FROM [dbo].[posRewardCatalogItems] WHERE companyId = @companyId AND code = @code)
            BEGIN
                SELECT '{"error":"code already exists for this company"}' AS jsonResult;
                RETURN;
            END
            INSERT INTO [dbo].[posRewardCatalogItems]
                (companyId, name, rewardType, requiredPoints, discountValue, freeProductId, isActive, description,
                 code, startAtUtc, endAtUtc, firstPurchaseOnly)
            VALUES (@companyId, @name, 'coupon_b2g1', 0, NULL, @productId, ISNULL(@isActive, 1), @description,
                    @code, @startAtUtc, @endAtUtc, ISNULL(@firstPurchaseOnly, 0));
        END
        ELSE IF @action = 2
        BEGIN
            UPDATE [dbo].[posRewardCatalogItems] SET
                name              = ISNULL(NULLIF(LTRIM(@name), ''), name),
                description       = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'description') THEN @description ELSE description END,
                startAtUtc        = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'startAtUtc')  THEN @startAtUtc  ELSE startAtUtc END,
                endAtUtc          = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'endAtUtc')    THEN @endAtUtc    ELSE endAtUtc END,
                freeProductId     = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'productId')   THEN @productId   ELSE freeProductId END,
                firstPurchaseOnly = ISNULL(@firstPurchaseOnly, firstPurchaseOnly),
                isActive          = ISNULL(@isActive, isActive),
                updated_at        = GETUTCDATE()
            WHERE catalogItemId = @promotionId AND companyId = @companyId AND rewardType = 'coupon_b2g1';
        END
        ELSE IF @action = 3
        BEGIN
            UPDATE [dbo].[posRewardCatalogItems] SET isActive = 0, updated_at = GETUTCDATE()
            WHERE catalogItemId = @promotionId AND companyId = @companyId AND rewardType = 'coupon_b2g1';
        END

        -- activeOnly: same validity rule sp_income_applyDiscounts applies at checkout.
        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT catalogItemId AS promotionId, companyId, code, name, 'B2G1' AS promoType, description, isActive,
                   CONVERT(NVARCHAR(19), startAtUtc, 126) AS startAtUtc,
                   CONVERT(NVARCHAR(19), endAtUtc, 126)   AS endAtUtc,
                   freeProductId AS productId, firstPurchaseOnly
            FROM [dbo].[posRewardCatalogItems]
            WHERE companyId = @companyId AND rewardType = 'coupon_b2g1'
              AND (@activeOnly = 0 OR (
                    isActive = 1
                    AND (startAtUtc IS NULL OR startAtUtc <= @nowUtc)
                    AND (endAtUtc   IS NULL OR endAtUtc   >= @nowUtc)))
            ORDER BY CASE WHEN endAtUtc IS NULL THEN 1 ELSE 0 END, endAtUtc, catalogItemId DESC
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"promotions":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;

    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
