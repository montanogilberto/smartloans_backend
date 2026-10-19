-- ============================================================
-- A WhatsApp customer's OWN reward points, looked up by the phone they are
-- writing from (WhatsApp authenticates the sender's number). Read-only.
-- Only reachable through POST /whatsapp/assistant/customerRewards, which
-- requires the X-Worker-Key — never a public "points by phone" lookup.
--
-- Matches the company's active clients on the last 10 digits of
-- cellphone. Excludes the POS walk-in placeholder ("Desconocido"): it
-- collects anonymous sales and may carry a staff member's phone, so its
-- points belong to no one.
--   → {"result":[{"status":"found","clientId","firstName","balance",
--                 "lifetimeEarned","redeemable":[...]}]}
--   → {"result":[{"status":"not_found"}]} / {"status":"ambiguous"}
-- ============================================================

IF OBJECT_ID('dbo.sp_whatsappCustomerRewards', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_whatsappCustomerRewards;
GO
CREATE PROCEDURE [dbo].[sp_whatsappCustomerRewards]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.customerRewards[0].companyId'));
        DECLARE @phone     NVARCHAR(30) = JSON_VALUE(@pjsonfile, '$.customerRewards[0].phone');
        DECLARE @digits    NVARCHAR(30) = RIGHT(REPLACE(REPLACE(REPLACE(ISNULL(@phone, ''), '+', ''), ' ', ''), '-', ''), 10);

        IF @companyId IS NULL OR LEN(@digits) < 10
        BEGIN
            SELECT '{"error":"companyId and phone are required"}' AS jsonResult;
            RETURN;
        END

        DECLARE @matches TABLE (clientId INT, firstName NVARCHAR(100));
        INSERT INTO @matches (clientId, firstName)
        SELECT c.clientId, c.first_name
        FROM [dbo].[clients] c
        WHERE c.companyId = @companyId
          AND c.isActive = 1
          AND c.first_name <> N'Desconocido'
          AND RIGHT(REPLACE(REPLACE(REPLACE(c.cellphone, '+', ''), ' ', ''), '-', ''), 10) = @digits;

        DECLARE @n INT = (SELECT COUNT(*) FROM @matches);
        IF @n = 0
        BEGIN
            SELECT '{"result":[{"status":"not_found"}]}' AS jsonResult;
            RETURN;
        END
        IF @n > 1
        BEGIN
            SELECT '{"result":[{"status":"ambiguous"}]}' AS jsonResult;
            RETURN;
        END

        DECLARE @clientId INT, @firstName NVARCHAR(100);
        SELECT @clientId = clientId, @firstName = firstName FROM @matches;

        DECLARE @balance DECIMAL(12,2) = 0, @earned DECIMAL(12,2) = 0;
        SELECT @balance = balance, @earned = lifetimeEarned
        FROM [dbo].[posRewardBalances]
        WHERE companyId = @companyId AND clientId = @clientId;

        -- Points rewards are judged on the balance; stamp cards (free_product)
        -- on units bought of that product (fn_posRewardStampStatus, the rule
        -- the POS redeems with). Coupons are typed at checkout,
        -- not redeemed, so they're not listed here (see get_promotions).
        DECLARE @redeemable NVARCHAR(MAX) = (
            SELECT s.name, s.rewardType, s.requiredPoints, s.discountValue, s.description,
                   s.requiredUnits, s.unitsAvailable,
                   CAST(CASE WHEN s.rewardType = 'free_product' THEN CASE WHEN s.unitsAvailable >= s.requiredUnits THEN 1 ELSE 0 END
                             WHEN s.requiredPoints <= ISNULL(@balance, 0) THEN 1 ELSE 0 END AS BIT) AS canRedeemNow
            FROM (
                SELECT c.name, c.rewardType, c.requiredPoints, c.discountValue, c.description,
                       st.requiredUnits, st.unitsAvailable
                FROM [dbo].[posRewardCatalogItems] c
                LEFT JOIN [dbo].[fn_posRewardStampStatus](@companyId, @clientId, NULL) st
                       ON st.catalogItemId = c.catalogItemId
                WHERE c.companyId = @companyId AND c.isActive = 1 AND c.rewardType <> 'coupon_b2g1'
            ) s
            ORDER BY CASE WHEN s.rewardType = 'free_product' THEN 0 ELSE 1 END, s.requiredPoints, s.name
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );

        DECLARE @out NVARCHAR(MAX) = (
            SELECT 'found' AS status, @clientId AS clientId, @firstName AS firstName,
                   ISNULL(@balance, 0) AS balance, ISNULL(@earned, 0) AS lifetimeEarned,
                   JSON_QUERY(ISNULL(@redeemable, '[]')) AS redeemable
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
        SELECT ('{"result":[' + @out + ']}') AS jsonResult;

    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
