-- ============================================================
-- Business info for the WhatsApp assistant (address, phone, payment
-- methods, prices…). One company-wide row (branchId NULL) plus optional
-- per-branch rows.
--   0  get — for a branch: each field from the branch row, falling back to
--      the company-wide row when the branch leaves it empty
--   1  upsert the row for (companyId, branchId); only keys sent change
-- Table: sql/migrations/2026-10-16_whatsapp_assistant_catalogs.sql
-- ============================================================

IF OBJECT_ID('dbo.sp_businessInfo', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_businessInfo;
GO
CREATE PROCEDURE [dbo].[sp_businessInfo]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action    INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.businessInfo[0].action'));
        DECLARE @companyId INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.businessInfo[0].companyId'));
        DECLARE @branchId  INT            = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.businessInfo[0].branchId'));
        DECLARE @address   NVARCHAR(300)  = JSON_VALUE(@pjsonfile, '$.businessInfo[0].address');
        DECLARE @mapsUrl   NVARCHAR(500)  = JSON_VALUE(@pjsonfile, '$.businessInfo[0].mapsUrl');
        DECLARE @phone     NVARCHAR(30)   = JSON_VALUE(@pjsonfile, '$.businessInfo[0].phone');
        DECLARE @email     NVARCHAR(120)  = JSON_VALUE(@pjsonfile, '$.businessInfo[0].email');
        DECLARE @payments  NVARCHAR(300)  = JSON_VALUE(@pjsonfile, '$.businessInfo[0].paymentMethods');
        DECLARE @services  NVARCHAR(2000) = JSON_VALUE(@pjsonfile, '$.businessInfo[0].servicesInfo');
        DECLARE @extra     NVARCHAR(2000) = JSON_VALUE(@pjsonfile, '$.businessInfo[0].extraInfo');

        -- OPENJSON key list (JSON_PATH_EXISTS needs SQL Server 2022).
        DECLARE @keys TABLE ([key] NVARCHAR(100));
        INSERT INTO @keys SELECT [key] FROM OPENJSON(@pjsonfile, '$.businessInfo[0]');

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END

        IF @action = 1
        BEGIN
            IF @branchId IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM [dbo].[companiesBranch] WHERE branchId = @branchId AND companyId = @companyId)
            BEGIN
                SELECT '{"error":"branchId does not belong to companyId"}' AS jsonResult;
                RETURN;
            END
            IF NOT EXISTS (SELECT 1 FROM [dbo].[businessInfo]
                           WHERE companyId = @companyId AND ISNULL(branchId, -1) = ISNULL(@branchId, -1))
                INSERT INTO [dbo].[businessInfo] (companyId, branchId) VALUES (@companyId, @branchId);

            UPDATE [dbo].[businessInfo] SET
                address        = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'address')        THEN @address  ELSE address END,
                mapsUrl        = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'mapsUrl')        THEN @mapsUrl  ELSE mapsUrl END,
                phone          = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'phone')          THEN @phone    ELSE phone END,
                email          = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'email')          THEN @email    ELSE email END,
                paymentMethods = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'paymentMethods') THEN @payments ELSE paymentMethods END,
                servicesInfo   = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'servicesInfo')   THEN @services ELSE servicesInfo END,
                extraInfo      = CASE WHEN EXISTS (SELECT 1 FROM @keys WHERE [key] = 'extraInfo')      THEN @extra    ELSE extraInfo END,
                updatedAt      = GETUTCDATE()
            WHERE companyId = @companyId AND ISNULL(branchId, -1) = ISNULL(@branchId, -1);
        END

        DECLARE @infoJson NVARCHAR(MAX) = (
            SELECT co.companyId, co.name AS companyName,
                   br.branchId, br.name AS branchName,
                   COALESCE(b.address,        c.address)        AS address,
                   COALESCE(b.mapsUrl,        c.mapsUrl)        AS mapsUrl,
                   COALESCE(b.phone,          c.phone)          AS phone,
                   COALESCE(b.email,          c.email)          AS email,
                   COALESCE(b.paymentMethods, c.paymentMethods) AS paymentMethods,
                   COALESCE(b.servicesInfo,   c.servicesInfo)   AS servicesInfo,
                   COALESCE(b.extraInfo,      c.extraInfo)      AS extraInfo
            FROM [dbo].[companies] co
            LEFT JOIN [dbo].[companiesBranch] br ON br.branchId = @branchId AND br.companyId = co.companyId
            LEFT JOIN [dbo].[businessInfo] c ON c.companyId = co.companyId AND c.branchId IS NULL
            LEFT JOIN [dbo].[businessInfo] b ON b.companyId = co.companyId AND @branchId IS NOT NULL AND b.branchId = @branchId
            WHERE co.companyId = @companyId
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"businessInfo":' + ISNULL(@infoJson, '[]') + '}]}') AS jsonResult;

    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
