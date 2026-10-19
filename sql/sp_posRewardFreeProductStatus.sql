-- ─────────────────────────────────────────────────────────────────────────────
-- sp_posRewardFreeProductStatus
-- Per active free_product catalog item, whether this client can redeem it:
-- fn_posRewardStampStatus, the same rule sp_posRewardRedemptions_redeem and
-- sp_income_applyDiscounts use (free_product rewards are earned by buying
-- that product, never from the points balance). Read-only; used by the sale
-- message's rewards line (modules/posRewards.py).
-- Input:  { "posRewardFreeProductStatus": [{ "companyId": int, "clientId": int }] }
-- Output: { "result": [{ "posRewardFreeProductStatus": [{ "catalogItemId", "freeProductId",
--           "requiredUnits", "unitsPurchased", "unitsAvailable" }] }] }
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.sp_posRewardFreeProductStatus', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardFreeProductStatus;
GO
CREATE PROCEDURE [dbo].[sp_posRewardFreeProductStatus]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardFreeProductStatus[0].companyId'));
        DECLARE @clientId  INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardFreeProductStatus[0].clientId'));

        IF @companyId IS NULL OR @clientId IS NULL
        BEGIN
            SELECT ('{"error":"companyId and clientId are required"}') AS [jsonResult];
            RETURN;
        END

        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT catalogItemId, freeProductId, requiredUnits, unitsPurchased, unitsAvailable
            FROM [dbo].[fn_posRewardStampStatus](@companyId, @clientId, NULL)
            WHERE isActive = 1
            ORDER BY catalogItemId
            FOR JSON PATH
        );
        SELECT ('{"result":[{"posRewardFreeProductStatus":' + ISNULL(@listJson, '[]') + '}]}') AS [jsonResult];

    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
