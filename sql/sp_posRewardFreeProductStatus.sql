-- ─────────────────────────────────────────────────────────────────────────────
-- sp_posRewardFreeProductStatus
-- Per active free_product catalog item, whether this client can redeem it —
-- the SAME unit check sp_posRewardRedemptions_redeem runs (free_product
-- rewards are earned by buying that product, never from the points balance):
--   requiredUnits  = catalog requiredUnits; legacy rows: requiredPoints / pointsPerUnit
--                    (active rate), else requiredPoints
--   unitsPurchased = SUM(incomeDetails.quantity) of freeProductId, this client + company
--   unitsAvailable = unitsPurchased - applied redemptions of this item * requiredUnits
-- Keep in sync with the free_product block of sp_posRewardRedemptions_redeem
-- (sql/sp_posRewards.sql). Read-only; used by the sale message's rewards line
-- (modules/posRewards.py).
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
            SELECT s.catalogItemId, s.freeProductId, s.requiredUnits, s.unitsPurchased,
                   s.unitsPurchased - s.priorRedemptions * s.requiredUnits AS unitsAvailable
            FROM (
                SELECT c.catalogItemId, c.freeProductId,
                       CAST(COALESCE(c.requiredUnits,
                                CASE WHEN ISNULL(r.pointsPerUnit, 0) > 0 THEN c.requiredPoints / r.pointsPerUnit
                                     ELSE c.requiredPoints END) AS DECIMAL(12,2)) AS requiredUnits,
                       CAST(ISNULL((
                           SELECT SUM(d.quantity)
                           FROM [dbo].[incomeDetails] d
                           JOIN [dbo].[income] i ON i.incomeId = d.incomeId
                           WHERE d.productId = c.freeProductId AND i.clientId = @clientId AND i.companyId = @companyId
                       ), 0) AS DECIMAL(12,2)) AS unitsPurchased,
                       (SELECT COUNT(*) FROM [dbo].[posRewardRedemptions] rd
                        WHERE rd.companyId = @companyId AND rd.clientId = @clientId
                          AND rd.catalogItemId = c.catalogItemId AND rd.status = 'applied') AS priorRedemptions
                FROM [dbo].[posRewardCatalogItems] c
                OUTER APPLY (
                    SELECT TOP 1 pr.pointsPerUnit FROM [dbo].[posRewardProductRates] pr
                    WHERE pr.companyId = @companyId AND pr.productId = c.freeProductId AND pr.isActive = 1
                ) r
                WHERE c.companyId = @companyId AND c.isActive = 1
                  AND c.rewardType = 'free_product' AND c.freeProductId IS NOT NULL
            ) s
            ORDER BY s.catalogItemId
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
