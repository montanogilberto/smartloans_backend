-- =============================================================================
-- Client activity: how many sales (income) a client made + every reward given
-- =============================================================================
-- Read-only (SELECTs + one temp table). Run in SSMS against the live DB.
-- Set @clientId below (or NULL + @name to search by name). Matching ignores case and accents ("carlos corral" finds
-- "Carlos Corral" / "CARLOS CORRÁL") and works on first_name + last_name.
--
-- Two reward systems exist, both shown:
--   * Loyalty points  — dbo.rewardTransactions / dbo.rewardPoints
--                       (a POS sale earns with referenceId = incomeId as text;
--                        redemptions are stored as negative points)
--   * POS rewards     — dbo.posRewardTransactions / dbo.posRewardBalances /
--                       dbo.posRewardRedemptions
--                       (referenceType 'ticket' + referenceId = incomeId;
--                        points always positive, direction C/D is the sign —
--                        shown signed below so both systems read the same)
--
-- Result sets:
--   1. Matching clients (check it's the right person / company)
--   2. Summary per client: sales count, spend, points earned/redeemed, balances
--   3. Every sale, with the points it earned in each system
--   4. Full rewards history (both systems, newest first)
--   5. POS reward redemptions (what was redeemed, on which sale)
-- =============================================================================

DECLARE @clientId INT          = 2260;             -- set to NULL to search by name
DECLARE @name     NVARCHAR(200) = N'Carlos Corral';  -- used only when @clientId IS NULL

IF OBJECT_ID('tempdb..#c') IS NOT NULL DROP TABLE #c;

SELECT c.clientId, c.companyId, c.first_name, c.last_name, c.cellphone, c.email, c.created_At
INTO #c
FROM dbo.clients c
WHERE (@clientId IS NOT NULL AND c.clientId = @clientId)
   OR (@clientId IS NULL
       AND LTRIM(RTRIM(CONCAT(c.first_name, N' ', c.last_name))) COLLATE Latin1_General_CI_AI
           LIKE N'%' + @name + N'%' COLLATE Latin1_General_CI_AI);

-- 1. Matching clients ------------------------------------------------------------
SELECT * FROM #c ORDER BY clientId;

-- 2. Summary per client ----------------------------------------------------------
SELECT
    c.clientId,
    c.companyId,
    CONCAT(c.first_name, N' ', c.last_name)                AS client,
    ISNULL(inc.salesCount, 0)                              AS salesCount,
    ISNULL(inc.totalSpent, 0)                              AS totalSpent,
    inc.firstSale,
    inc.lastSale,
    ISNULL(lp.pointsEarned, 0)                             AS loyaltyPointsEarned,
    ISNULL(lp.pointsRedeemed, 0)                           AS loyaltyPointsRedeemed,
    rp.balance                                             AS loyaltyBalance,
    ISNULL(pr.pointsEarned, 0)                             AS posPointsEarned,
    ISNULL(pr.pointsRedeemed, 0)                           AS posPointsRedeemed,
    pb.balance                                             AS posBalance,
    ISNULL(rd.redemptions, 0)                              AS posRedemptions
FROM #c c
OUTER APPLY (
    SELECT COUNT(*) AS salesCount, SUM(i.total) AS totalSpent,
           MIN(i.paymentDate) AS firstSale, MAX(i.paymentDate) AS lastSale
    FROM dbo.income i
    WHERE i.clientId = c.clientId AND i.companyId = c.companyId
) inc
OUTER APPLY (
    SELECT SUM(CASE WHEN rt.points > 0 THEN rt.points ELSE 0 END)       AS pointsEarned,
           SUM(CASE WHEN rt.points < 0 THEN -rt.points ELSE 0 END)      AS pointsRedeemed
    FROM dbo.rewardTransactions rt
    WHERE rt.clientId = c.clientId AND rt.companyId = c.companyId
) lp
OUTER APPLY (
    SELECT TOP 1 balance FROM dbo.rewardPoints
    WHERE clientId = c.clientId AND companyId = c.companyId
) rp
OUTER APPLY (
    -- points is always positive; direction carries the sign (C = credit, D = debit)
    SELECT SUM(CASE WHEN pt.direction = 'C' THEN pt.points ELSE 0 END) AS pointsEarned,
           SUM(CASE WHEN pt.direction = 'D' THEN pt.points ELSE 0 END) AS pointsRedeemed
    FROM dbo.posRewardTransactions pt
    WHERE pt.clientId = c.clientId AND pt.companyId = c.companyId
) pr
OUTER APPLY (
    SELECT TOP 1 balance FROM dbo.posRewardBalances
    WHERE clientId = c.clientId AND companyId = c.companyId
) pb
OUTER APPLY (
    SELECT COUNT(*) AS redemptions FROM dbo.posRewardRedemptions
    WHERE clientId = c.clientId AND companyId = c.companyId
) rd
ORDER BY c.clientId;

-- 3. Every sale with the points it earned -----------------------------------------
SELECT
    i.incomeId,
    i.clientId,
    DATEADD(HOUR, -7, i.paymentDate)                       AS paymentDateHermosillo,
    i.paymentMethod,
    i.total,
    ISNULL(i.discountAmount, 0)                            AS discountAmount,
    i.promotionCode,
    (SELECT ISNULL(SUM(rt.points), 0) FROM dbo.rewardTransactions rt
      WHERE rt.clientId = i.clientId AND rt.companyId = i.companyId
        AND rt.referenceId = CAST(i.incomeId AS NVARCHAR(100)))          AS loyaltyPoints,
    (SELECT ISNULL(SUM(CASE WHEN pt.direction = 'D' THEN -pt.points ELSE pt.points END), 0)
       FROM dbo.posRewardTransactions pt
      WHERE pt.clientId = i.clientId AND pt.companyId = i.companyId
        AND pt.referenceType = 'ticket' AND pt.referenceId = i.incomeId) AS posPoints
FROM dbo.income i
JOIN #c c ON c.clientId = i.clientId AND c.companyId = i.companyId
ORDER BY i.paymentDate DESC;

-- 4. Full rewards history (both systems) ------------------------------------------
SELECT * FROM (
    SELECT 'loyalty'        AS system, rt.clientId, rt.created_At AS createdAt,
           rt.txType, rt.points, rt.balanceAfter,
           rt.referenceId   AS reference, rt.description
    FROM dbo.rewardTransactions rt
    JOIN #c c ON c.clientId = rt.clientId AND c.companyId = rt.companyId
    UNION ALL
    SELECT 'pos'            AS system, pt.clientId, pt.created_At,
           pt.txType, CASE WHEN pt.direction = 'D' THEN -pt.points ELSE pt.points END, pt.balanceAfter,
           CONCAT(pt.referenceType, N':', pt.referenceId), pt.description
    FROM dbo.posRewardTransactions pt
    JOIN #c c ON c.clientId = pt.clientId AND c.companyId = pt.companyId
) h
ORDER BY h.createdAt DESC;

-- 5. POS reward redemptions -------------------------------------------------------
SELECT r.redemptionId, r.clientId, r.created_At, r.pointsSpent, r.status, r.incomeId,
       ci.name AS rewardName, ci.rewardType, ci.discountValue
FROM dbo.posRewardRedemptions r
JOIN #c c ON c.clientId = r.clientId AND c.companyId = r.companyId
LEFT JOIN dbo.posRewardCatalogItems ci ON ci.catalogItemId = r.catalogItemId
ORDER BY r.created_At DESC;

DROP TABLE #c;
