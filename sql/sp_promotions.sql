-- ============================================================
-- Promotions = the EXISTING dbo.promotions the POS applies at checkout
-- (sp_income / sp_income_apply_promo: code, promoType, startAtUtc/endAtUtc).
-- The WhatsApp assistant lists action 0 with activeOnly=1; the POS can
-- manage them with 0/1/2/3. promoType must be one the POS knows how to
-- apply (today: 'B2G1').
-- Column added by sql/migrations/2026-10-16_whatsapp_assistant_catalogs.sql:
-- description (customer-facing text for the assistant).
-- ============================================================

IF OBJECT_ID('dbo.sp_promotions', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_promotions;
GO
CREATE PROCEDURE [dbo].[sp_promotions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action      INT           = TRY_CONVERT(INT,       JSON_VALUE(@pjsonfile, '$.promotions[0].action'));
        DECLARE @companyId   INT           = TRY_CONVERT(INT,       JSON_VALUE(@pjsonfile, '$.promotions[0].companyId'));
        DECLARE @promotionId INT           = TRY_CONVERT(INT,       JSON_VALUE(@pjsonfile, '$.promotions[0].promotionId'));
        DECLARE @code        VARCHAR(30)   = UPPER(LTRIM(RTRIM(     JSON_VALUE(@pjsonfile, '$.promotions[0].code'))));
        DECLARE @name        NVARCHAR(160) =                        JSON_VALUE(@pjsonfile, '$.promotions[0].name');
        DECLARE @promoType   VARCHAR(20)   =                        JSON_VALUE(@pjsonfile, '$.promotions[0].promoType');
        DECLARE @description NVARCHAR(500) =                        JSON_VALUE(@pjsonfile, '$.promotions[0].description');
        DECLARE @startAtUtc  DATETIME2     = TRY_CONVERT(DATETIME2, JSON_VALUE(@pjsonfile, '$.promotions[0].startAtUtc'));
        DECLARE @endAtUtc    DATETIME2     = TRY_CONVERT(DATETIME2, JSON_VALUE(@pjsonfile, '$.promotions[0].endAtUtc'));
        DECLARE @isActive    BIT           = TRY_CONVERT(BIT,       JSON_VALUE(@pjsonfile, '$.promotions[0].isActive'));
        DECLARE @activeOnly  BIT           = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.promotions[0].activeOnly')), 0);
        DECLARE @nowUtc      DATETIME2     = SYSUTCDATETIME();

        -- Keys present in the payload (action 2 only changes those). OPENJSON
        -- because JSON_PATH_EXISTS needs SQL Server 2022 (DB compat is 130).
        DECLARE @keys TABLE ([key] NVARCHAR(100));
        INSERT INTO @keys SELECT [key] FROM OPENJSON(@pjsonfile, '$.promotions[0]');

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END

        IF @action = 1
        BEGIN
            IF NULLIF(@code, '') IS NULL OR NULLIF(LTRIM(@name), '') IS NULL OR NULLIF(@promoType, '') IS NULL
            BEGIN
                SELECT '{"error":"code, name and promoType are required"}' AS jsonResult;
                RETURN;
            END
            IF EXISTS (SELECT 1 FROM [dbo].[promotions] WHERE companyId = @companyId AND code = @code)
            BEGIN
                SELECT '{"error":"code already exists for this company"}' AS jsonResult;
                RETURN;
            END
            INSERT INTO [dbo].[promotions] (companyId, code, name, promoType, isActive, startAtUtc, endAtUtc, createdAtUtc, description)
            VALUES (@companyId, @code, @name, @promoType, ISNULL(@isActive, 1), @startAtUtc, @endAtUtc, @nowUtc, @description);
        END
        ELSE IF @action = 2
        BEGIN
            UPDATE [dbo].[promotions] SET
                name        = ISNULL(NULLIF(LTRIM(@name), ''), name),
                promoType   = ISNULL(NULLIF(@promoType, ''), promoType),
                description = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'description') THEN @description ELSE description END,
                startAtUtc  = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'startAtUtc')  THEN @startAtUtc  ELSE startAtUtc END,
                endAtUtc    = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'endAtUtc')    THEN @endAtUtc    ELSE endAtUtc END,
                isActive    = ISNULL(@isActive, isActive)
            WHERE promotionId = @promotionId AND companyId = @companyId;
        END
        ELSE IF @action = 3
        BEGIN
            UPDATE [dbo].[promotions] SET isActive = 0
            WHERE promotionId = @promotionId AND companyId = @companyId;
        END

        -- activeOnly: same validity rule sp_income applies at checkout.
        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT promotionId, companyId, code, name, promoType, description, isActive,
                   CONVERT(NVARCHAR(19), startAtUtc, 126) AS startAtUtc,
                   CONVERT(NVARCHAR(19), endAtUtc, 126)   AS endAtUtc
            FROM [dbo].[promotions]
            WHERE companyId = @companyId
              AND (@activeOnly = 0 OR (
                    isActive = 1
                    AND (startAtUtc IS NULL OR startAtUtc <= @nowUtc)
                    AND (endAtUtc   IS NULL OR endAtUtc   >= @nowUtc)))
            ORDER BY CASE WHEN endAtUtc IS NULL THEN 1 ELSE 0 END, endAtUtc, promotionId DESC
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
