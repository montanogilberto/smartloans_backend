-- ============================================================
-- Promotion targets = which sale lines a promotion discounts
-- (dbo.promotion_targets, read by sp_income and sp_income_apply_promo).
-- A promotion targets EITHER everything ('ALL', one row) OR a list of
-- products ('PRODUCT' rows). Adding ALL replaces the product list; adding a
-- PRODUCT removes ALL. A promotion with no targets discounts nothing.
--
--   action 0 — list a promotion's targets
--   action 1 — add: targetType 'ALL' | 'PRODUCT' (+ productId)
--   action 3 — remove: promotionTargetId
-- Every action returns the promotion's current target list.
-- ============================================================

IF OBJECT_ID('dbo.sp_promotionTargets', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_promotionTargets;
GO
CREATE PROCEDURE [dbo].[sp_promotionTargets]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action            INT         = ISNULL(TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.promotionTargets[0].action')), 0);
        DECLARE @companyId         INT         = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.promotionTargets[0].companyId'));
        DECLARE @promotionId       INT         = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.promotionTargets[0].promotionId'));
        DECLARE @promotionTargetId INT         = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.promotionTargets[0].promotionTargetId'));
        DECLARE @targetType        VARCHAR(20) = UPPER(LTRIM(RTRIM(JSON_VALUE(@pjsonfile, '$.promotionTargets[0].targetType'))));
        DECLARE @productId         INT         = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.promotionTargets[0].productId'));

        IF @companyId IS NULL OR @promotionId IS NULL
        BEGIN
            SELECT '{"error":"companyId and promotionId are required"}' AS jsonResult;
            RETURN;
        END

        -- The promotion must belong to the company (targets have no companyId).
        IF NOT EXISTS (SELECT 1 FROM [dbo].[promotions] WHERE promotionId = @promotionId AND companyId = @companyId)
        BEGIN
            SELECT '{"error":"promotion not found for this company"}' AS jsonResult;
            RETURN;
        END

        IF @action = 1
        BEGIN
            IF @targetType = 'ALL'
            BEGIN
                BEGIN TRAN;
                    DELETE FROM [dbo].[promotion_targets] WHERE promotionId = @promotionId;
                    INSERT INTO [dbo].[promotion_targets] (promotionId, targetType, productId)
                    VALUES (@promotionId, 'ALL', NULL);
                COMMIT;
            END
            ELSE IF @targetType = 'PRODUCT'
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [dbo].[products] WHERE productId = @productId AND companyId = @companyId)
                BEGIN
                    SELECT '{"error":"productId not found for this company"}' AS jsonResult;
                    RETURN;
                END
                BEGIN TRAN;
                    DELETE FROM [dbo].[promotion_targets] WHERE promotionId = @promotionId AND targetType = 'ALL';
                    IF NOT EXISTS (SELECT 1 FROM [dbo].[promotion_targets]
                                   WHERE promotionId = @promotionId AND targetType = 'PRODUCT' AND productId = @productId)
                        INSERT INTO [dbo].[promotion_targets] (promotionId, targetType, productId)
                        VALUES (@promotionId, 'PRODUCT', @productId);
                COMMIT;
            END
            ELSE
            BEGIN
                SELECT '{"error":"targetType must be ALL or PRODUCT"}' AS jsonResult;
                RETURN;
            END
        END
        ELSE IF @action = 3
        BEGIN
            DELETE FROM [dbo].[promotion_targets]
            WHERE promotionTargetId = @promotionTargetId AND promotionId = @promotionId;
        END

        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT t.promotionTargetId, t.promotionId, t.targetType, t.productId, pr.name AS productName
            FROM [dbo].[promotion_targets] t
            LEFT JOIN [dbo].[products] pr ON pr.productId = t.productId
            WHERE t.promotionId = @promotionId
            ORDER BY CASE WHEN t.targetType = 'ALL' THEN 0 ELSE 1 END, pr.name
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"promotionTargets":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
