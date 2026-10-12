-- =============================================================================
-- Client tickets: line-by-line breakdown, services applied, and rewards list
-- =============================================================================
-- Read-only (SELECTs only). Run in SSMS against the live DB. Set @clientId.
--
-- How a ticket is priced (same rule as sp_tickets_one, the printed ticket):
--   a product line's base price is 0 — the SERVICE price comes from the option
--   choices picked for it:  line = SUM(productOptionChoices.price × option qty).
--   income.total is what was charged (already after any 2x1 discount).
-- Caveat: incomeDetails stores no price, so line amounts use TODAY's choice
-- prices. If a price changed after the sale, "linesSubtotal" will not match
-- the stored total — result set 1 shows the difference so it's visible.
--
-- Result sets:
--   1. Tickets (one row per sale): totals, discount/promo, commission, points
--   2. Ticket lines: product -> option -> choice (the service applied), qty, price
--   3. Services applied: how many times each service/choice was bought, and $
--   4. Rewards list: every point earned/redeemed, both systems, newest first
--   5. Rewards redeemed (POS catalog) and what the client can redeem now
-- =============================================================================

DECLARE @clientId INT = 2260;

DECLARE @companyId INT = (SELECT companyId FROM dbo.clients WHERE clientId = @clientId);

-- Option lines priced like the ticket ---------------------------------------------
IF OBJECT_ID('tempdb..#lines') IS NOT NULL DROP TABLE #lines;

SELECT
    i.incomeId,
    d.incomeDetailId,
    d.productId,
    p.name                                         AS product,
    cat.name                                       AS category,
    d.quantity                                     AS productQty,
    o.name                                         AS optionName,
    ch.name                                        AS service,
    CAST(ch.price AS DECIMAL(10,2))                AS unitPrice,
    ISNULL(ido.quantity, 1)                        AS serviceQty,
    CAST(ISNULL(ch.price, 0) * ISNULL(ido.quantity, 1) AS DECIMAL(10,2)) AS amount,
    d.piecesJson
INTO #lines
FROM dbo.income i
JOIN dbo.incomeDetails d              ON d.incomeId = i.incomeId
LEFT JOIN dbo.products p              ON p.productId = d.productId
LEFT JOIN dbo.productCategories cat   ON cat.productCategoryId = p.categoryId
LEFT JOIN dbo.incomeDetailOptions ido ON ido.incomeDetailId = d.incomeDetailId
LEFT JOIN dbo.productOptions o        ON o.productOptionId = ido.productOptionId
LEFT JOIN dbo.productOptionChoices ch ON ch.productOptionChoiceId = ido.productOptionChoiceId
WHERE i.clientId = @clientId AND i.companyId = @companyId;

-- 1. Tickets ------------------------------------------------------------------------
SELECT
    i.incomeId                                      AS ticket,
    DATEADD(HOUR, -7, i.paymentDate)                AS dateHermosillo,
    i.paymentMethod,
    (SELECT COUNT(DISTINCT incomeDetailId) FROM #lines l WHERE l.incomeId = i.incomeId) AS products,
    (SELECT ISNULL(SUM(amount), 0) FROM #lines l WHERE l.incomeId = i.incomeId)         AS linesSubtotal,
    ISNULL(i.discountAmount, 0)                     AS discount,
    i.promotionCode,
    i.total                                         AS charged,
    i.total + ISNULL(i.discountAmount, 0)
      - (SELECT ISNULL(SUM(amount), 0) FROM #lines l WHERE l.incomeId = i.incomeId)     AS priceDifference,
    ISNULL(i.commissionAmount, 0)                   AS terminalCommission,
    (SELECT ISNULL(SUM(rt.points), 0) FROM dbo.rewardTransactions rt
      WHERE rt.clientId = i.clientId AND rt.companyId = i.companyId
        AND rt.referenceId = CAST(i.incomeId AS NVARCHAR(100)))                         AS loyaltyPoints,
    (SELECT ISNULL(SUM(CASE WHEN pt.direction = 'D' THEN -pt.points ELSE pt.points END), 0)
       FROM dbo.posRewardTransactions pt
      WHERE pt.clientId = i.clientId AND pt.companyId = i.companyId
        AND pt.referenceType = 'ticket' AND pt.referenceId = i.incomeId)                AS posPoints
FROM dbo.income i
WHERE i.clientId = @clientId AND i.companyId = @companyId
ORDER BY i.paymentDate;

-- 2. Ticket lines (service applied per product) -------------------------------------
SELECT incomeId AS ticket, product, category, productQty, optionName, service,
       unitPrice, serviceQty, amount, piecesJson
FROM #lines
ORDER BY incomeId, incomeDetailId, optionName;

-- 3. Services applied (across all of this client's tickets) -------------------------
SELECT
    product,
    ISNULL(service, N'(sin servicio / opción)')     AS service,
    COUNT(DISTINCT incomeId)                         AS tickets,
    SUM(serviceQty)                                  AS timesApplied,
    SUM(amount)                                      AS amount,
    STRING_AGG(CAST(incomeId AS NVARCHAR(20)), ', ') AS ticketIds
FROM #lines
GROUP BY product, service
ORDER BY amount DESC, timesApplied DESC;

-- 4. Rewards list (both systems, signed: redemptions negative) ----------------------
SELECT * FROM (
    SELECT N'Puntos lealtad'  AS rewardSystem, rt.created_At AS createdAt, rt.txType,
           CAST(rt.points AS DECIMAL(12,2)) AS points, CAST(rt.balanceAfter AS DECIMAL(12,2)) AS balanceAfter,
           TRY_CONVERT(INT, rt.referenceId) AS ticket, rt.description
    FROM dbo.rewardTransactions rt
    WHERE rt.clientId = @clientId AND rt.companyId = @companyId
    UNION ALL
    SELECT N'Recompensas POS', pt.created_At, pt.txType,
           CASE WHEN pt.direction = 'D' THEN -pt.points ELSE pt.points END, pt.balanceAfter,
           CASE WHEN pt.referenceType = 'ticket' THEN pt.referenceId END, pt.description
    FROM dbo.posRewardTransactions pt
    WHERE pt.clientId = @clientId AND pt.companyId = @companyId
) r
ORDER BY r.createdAt DESC;

-- 5. POS rewards: redeemed so far, and what the current balance can redeem ----------
SELECT N'canjeado' AS kind, r.created_At AS createdAt, ci.name AS reward, ci.rewardType,
       r.pointsSpent AS points, ci.discountValue, r.status, r.incomeId AS ticket
FROM dbo.posRewardRedemptions r
LEFT JOIN dbo.posRewardCatalogItems ci ON ci.catalogItemId = r.catalogItemId
WHERE r.clientId = @clientId AND r.companyId = @companyId
UNION ALL
SELECT N'disponible', NULL, ci.name, ci.rewardType, ci.requiredPoints, ci.discountValue,
       CASE WHEN ISNULL(b.balance, 0) >= ci.requiredPoints
            THEN N'alcanza' ELSE CONCAT(N'faltan ', ci.requiredPoints - ISNULL(b.balance, 0), N' pts') END,
       NULL
FROM dbo.posRewardCatalogItems ci
LEFT JOIN dbo.posRewardBalances b ON b.clientId = @clientId AND b.companyId = ci.companyId
WHERE ci.companyId = @companyId AND ci.isActive = 1
ORDER BY kind, createdAt DESC, points;

DROP TABLE #lines;
