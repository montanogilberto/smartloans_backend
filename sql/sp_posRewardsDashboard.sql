-- ─────────────────────────────────────────────────────────────────────────────
-- sp_posRewardsDashboard — everything about rewards for one company, read-only
-- (POS "Puntos POS" › Resumen). One call, one JSON:
--   kpis         points earned / redeemed / adjusted in the period, outstanding
--                points (current balances; 1 pt = $1 when posRewardSettings.earnPct
--                is set), clients with balance, active clients, redemptions,
--                coupon uses, discount given on sales
--   daily        earned / redeemed per day
--   topCustomers top 10 current balances, with names
--   coupons      per coupon: uses in the period and the discount on those sales
--   rewards      per points reward / stamp card: applied and cancelled
--                redemptions, points spent
--   stampCards   per stamp card: clients ready, 1 purchase away, in progress,
--                and the 10 closest (fn_posRewardStampStatus)
--   smartLoans   the SEPARATE SmartLoans rewards (dbo.rewardTransactions):
--                points earned in the period and whether its 'purchase' rule is
--                active — sales earning in both systems at once
-- Days are Hermosillo days (UTC-7, no DST): ledger timestamps are UTC,
-- income.paymentDate is already local.
-- Input:  { "posRewardsDashboard": [{ "companyId": int,
--           "startDate"?: "YYYY-MM-DD", "endDate"?: "YYYY-MM-DD" }] }
--         (default: the last 30 days)
-- Output: { "result": [{ "period", "kpis", "daily", "topCustomers", "coupons",
--           "rewards", "stampCards", "smartLoans" }] }
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.sp_posRewardsDashboard', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardsDashboard;
GO
CREATE PROCEDURE [dbo].[sp_posRewardsDashboard]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT  = TRY_CONVERT(INT,  JSON_VALUE(@pjsonfile, '$.posRewardsDashboard[0].companyId'));
        DECLARE @today     DATE = CONVERT(DATE, DATEADD(HOUR, -7, SYSUTCDATETIME()));
        DECLARE @endDate   DATE = ISNULL(TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.posRewardsDashboard[0].endDate')), @today);
        DECLARE @startDate DATE = ISNULL(TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.posRewardsDashboard[0].startDate')),
                                         DATEADD(DAY, -29, @endDate));
        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END

        -- Ledger rows of the period, on Hermosillo days.
        DECLARE @tx TABLE (clientId INT, txType NVARCHAR(20), direction NVARCHAR(1), points DECIMAL(12,2), day DATE);
        INSERT INTO @tx
        SELECT clientId, txType, direction, points, CONVERT(DATE, DATEADD(HOUR, -7, created_At))
        FROM [dbo].[posRewardTransactions]
        WHERE companyId = @companyId
          AND created_At >= DATEADD(HOUR, 7, CAST(@startDate AS DATETIME2))
          AND created_At <  DATEADD(HOUR, 7, CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2));

        DECLARE @red TABLE (catalogItemId INT, status NVARCHAR(20), pointsSpent DECIMAL(12,2));
        INSERT INTO @red
        SELECT catalogItemId, status, pointsSpent
        FROM [dbo].[posRewardRedemptions]
        WHERE companyId = @companyId
          AND created_At >= DATEADD(HOUR, 7, CAST(@startDate AS DATETIME2))
          AND created_At <  DATEADD(HOUR, 7, CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2));

        DECLARE @sales TABLE (incomeId INT, promotionId INT, discountAmount DECIMAL(12,2));
        INSERT INTO @sales
        SELECT incomeId, promotionId, ISNULL(discountAmount, 0)
        FROM [dbo].[income]
        WHERE companyId = @companyId
          AND paymentDate >= CAST(@startDate AS DATETIME2)
          AND paymentDate <  CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2);

        DECLARE @earnPct DECIMAL(5,2) = (SELECT earnPct FROM [dbo].[posRewardSettings] WHERE companyId = @companyId);
        DECLARE @outstanding DECIMAL(14,2) = ISNULL((SELECT SUM(balance) FROM [dbo].[posRewardBalances]
                                                     WHERE companyId = @companyId AND balance > 0), 0);

        DECLARE @kpis NVARCHAR(MAX) = (
            SELECT
                ISNULL((SELECT SUM(points) FROM @tx WHERE txType = 'EARN'), 0)   AS pointsEarned,
                ISNULL((SELECT SUM(points) FROM @tx WHERE txType = 'REDEEM'), 0) AS pointsRedeemed,
                ISNULL((SELECT SUM(CASE WHEN direction = 'C' THEN points ELSE -points END)
                        FROM @tx WHERE txType IN ('ADJUSTMENT', 'EXPIRE')), 0)    AS pointsAdjusted,
                @outstanding                                                      AS outstandingPoints,
                CASE WHEN @earnPct IS NOT NULL THEN @outstanding END              AS outstandingValueMxn,
                @earnPct                                                          AS earnPct,
                (SELECT COUNT(*) FROM [dbo].[posRewardBalances]
                 WHERE companyId = @companyId AND balance > 0)                    AS clientsWithBalance,
                (SELECT COUNT(DISTINCT clientId) FROM @tx WHERE txType = 'EARN')  AS activeClients,
                (SELECT COUNT(*) FROM @red WHERE status = 'applied')              AS redemptions,
                (SELECT COUNT(*) FROM @sales s
                 JOIN [dbo].[posRewardCatalogItems] c ON c.catalogItemId = s.promotionId AND c.rewardType = 'coupon_b2g1') AS couponUses,
                ISNULL((SELECT SUM(discountAmount) FROM @sales), 0)               AS discountGiven,
                (SELECT COUNT(*) FROM @sales)                                     AS sales
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

        DECLARE @daily NVARCHAR(MAX) = (
            SELECT CONVERT(NVARCHAR(10), day, 23) AS [date],
                   SUM(CASE WHEN txType = 'EARN' THEN points ELSE 0 END)   AS earned,
                   SUM(CASE WHEN txType = 'REDEEM' THEN points ELSE 0 END) AS redeemed
            FROM @tx GROUP BY day ORDER BY day
            FOR JSON PATH);

        DECLARE @top NVARCHAR(MAX) = (
            SELECT TOP 10 b.clientId,
                   LTRIM(RTRIM(CONCAT(c.first_name, N' ', c.last_name))) AS name,
                   b.balance, b.lifetimeEarned, b.lifetimeRedeemed,
                   CONVERT(NVARCHAR(19), b.lastActivity, 126) AS lastActivity
            FROM [dbo].[posRewardBalances] b
            LEFT JOIN [dbo].[clients] c ON c.clientId = b.clientId
            WHERE b.companyId = @companyId AND b.clientId <> 1
            ORDER BY b.balance DESC, b.lifetimeEarned DESC
            FOR JSON PATH);

        DECLARE @coupons NVARCHAR(MAX) = (
            SELECT c.catalogItemId, c.code, c.name, c.isActive, c.firstPurchaseOnly,
                   (SELECT COUNT(*) FROM @sales s WHERE s.promotionId = c.catalogItemId) AS uses,
                   ISNULL((SELECT SUM(s.discountAmount) FROM @sales s WHERE s.promotionId = c.catalogItemId), 0) AS discountTotal
            FROM [dbo].[posRewardCatalogItems] c
            WHERE c.companyId = @companyId AND c.rewardType = 'coupon_b2g1'
            ORDER BY c.isActive DESC, c.code
            FOR JSON PATH);

        DECLARE @rewards NVARCHAR(MAX) = (
            SELECT c.catalogItemId, c.name, c.rewardType, c.requiredPoints, c.isActive,
                   (SELECT COUNT(*) FROM @red r WHERE r.catalogItemId = c.catalogItemId AND r.status = 'applied')   AS redemptions,
                   (SELECT COUNT(*) FROM @red r WHERE r.catalogItemId = c.catalogItemId AND r.status = 'cancelled') AS cancelled,
                   ISNULL((SELECT SUM(r.pointsSpent) FROM @red r
                           WHERE r.catalogItemId = c.catalogItemId AND r.status = 'applied'), 0)                    AS pointsSpent
            FROM [dbo].[posRewardCatalogItems] c
            WHERE c.companyId = @companyId AND c.rewardType <> 'coupon_b2g1'
            ORDER BY CASE WHEN c.rewardType = 'free_product' THEN 1 ELSE 0 END, c.requiredPoints, c.name
            FOR JSON PATH);

        -- Stamp-card progress of every client who ever bought a stamp product.
        DECLARE @stamps TABLE (catalogItemId INT, clientId INT, requiredUnits DECIMAL(12,2), unitsAvailable DECIMAL(12,2));
        INSERT INTO @stamps
        SELECT st.catalogItemId, buyers.clientId, st.requiredUnits, st.unitsAvailable
        FROM (SELECT DISTINCT i.clientId
              FROM [dbo].[income] i
              JOIN [dbo].[incomeDetails] d ON d.incomeId = i.incomeId
              JOIN [dbo].[posRewardCatalogItems] c ON c.freeProductId = d.productId
                   AND c.companyId = @companyId AND c.rewardType = 'free_product' AND c.isActive = 1
              WHERE i.companyId = @companyId AND i.clientId <> 1) buyers
        CROSS APPLY [dbo].[fn_posRewardStampStatus](@companyId, buyers.clientId, NULL) st
        WHERE st.isActive = 1 AND st.unitsAvailable > 0;

        DECLARE @stampCards NVARCHAR(MAX) = (
            SELECT c.catalogItemId, c.name, c.freeProductId,
                   CAST(ISNULL(c.requiredUnits, c.requiredPoints) AS DECIMAL(12,2)) AS requiredUnits,
                   (SELECT COUNT(*) FROM @stamps s WHERE s.catalogItemId = c.catalogItemId AND s.unitsAvailable >= s.requiredUnits) AS ready,
                   (SELECT COUNT(*) FROM @stamps s WHERE s.catalogItemId = c.catalogItemId
                      AND s.unitsAvailable < s.requiredUnits AND s.requiredUnits - s.unitsAvailable <= 1)                     AS oneAway,
                   (SELECT COUNT(*) FROM @stamps s WHERE s.catalogItemId = c.catalogItemId AND s.unitsAvailable < s.requiredUnits) AS inProgress,
                   JSON_QUERY(ISNULL((
                       SELECT TOP 10 s.clientId, LTRIM(RTRIM(CONCAT(cl.first_name, N' ', cl.last_name))) AS name,
                              s.unitsAvailable, s.requiredUnits
                       FROM @stamps s LEFT JOIN [dbo].[clients] cl ON cl.clientId = s.clientId
                       WHERE s.catalogItemId = c.catalogItemId
                       ORDER BY s.requiredUnits - s.unitsAvailable, s.unitsAvailable DESC
                       FOR JSON PATH), '[]')) AS closest
            FROM [dbo].[posRewardCatalogItems] c
            WHERE c.companyId = @companyId AND c.rewardType = 'free_product' AND c.isActive = 1
            ORDER BY c.name
            FOR JSON PATH);

        -- SmartLoans rewards (separate system, modules/rewards.py) — only if installed.
        DECLARE @smartLoans NVARCHAR(MAX) = N'null';
        IF OBJECT_ID('dbo.rewardTransactions', 'U') IS NOT NULL AND OBJECT_ID('dbo.rewardRules', 'U') IS NOT NULL
            SET @smartLoans = (
                SELECT
                    CAST(CASE WHEN EXISTS (SELECT 1 FROM [dbo].[rewardRules]
                                           WHERE companyId = @companyId AND ruleType = 'purchase' AND isActive = 1)
                              THEN 1 ELSE 0 END AS BIT) AS purchaseRuleActive,
                    ISNULL(SUM(points), 0)     AS pointsEarned,
                    COUNT(*)                   AS transactions,
                    COUNT(DISTINCT clientId)   AS clients
                FROM [dbo].[rewardTransactions]
                WHERE companyId = @companyId AND txType = 'earn'
                  AND created_At >= DATEADD(HOUR, 7, CAST(@startDate AS DATETIME2))
                  AND created_At <  DATEADD(HOUR, 7, CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2))
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES);

        SELECT CONCAT(
            N'{"result":[{"period":{"startDate":"', CONVERT(NVARCHAR(10), @startDate, 23),
            N'","endDate":"', CONVERT(NVARCHAR(10), @endDate, 23), N'"}',
            N',"kpis":', @kpis,
            N',"daily":', ISNULL(@daily, N'[]'),
            N',"topCustomers":', ISNULL(@top, N'[]'),
            N',"coupons":', ISNULL(@coupons, N'[]'),
            N',"rewards":', ISNULL(@rewards, N'[]'),
            N',"stampCards":', ISNULL(@stampCards, N'[]'),
            N',"smartLoans":', ISNULL(@smartLoans, N'null'),
            N'}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS jsonResult;
    END CATCH
END
GO
