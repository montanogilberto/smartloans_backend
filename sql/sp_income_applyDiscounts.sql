-- ============================================================
-- sp_income_applyDiscounts — applies a sale's coupon and its loyalty reward
-- (all from dbo.posRewardCatalogItems) right after sp_income inserts it, and
-- writes the authoritative total. Called by modules/income.py; replaces the
-- B2G1 block inside sp_income (which read dbo.promotions) and
-- sp_income_apply_promo.
--
-- Input:
--   { "incomeDiscounts": [{ "companyId": int, "incomeId": int, "userId": int,
--       "couponCode"?: "2X1",
--       "rewardCatalogItemIds"?: [int] }] }   -- at most ONE reward per sale
--
-- Line prices = SUM(choice price * option qty) per incomeDetails line, the
-- same pricing sp_income's B2G1 engine used. Per line:
--   coupon_b2g1   2x1 = buy 2, pay 1: pay qty - FLOOR(qty/2) on lines of
--                 freeProductId, or all lines when NULL. Pairs form within a
--                 line (same product + options). firstPurchaseOnly = the
--                 client has no other sale at this company (deleted sales
--                 are gone from dbo.income, so they don't count).
--   free_product  one unit of freeProductId free, if fn_posRewardStampStatus
--                 (purchases before this sale, free units excluded) covers
--                 requiredUnits.
--   discount_*    $ (capped at the total) or % off the discounted total;
--                 debits requiredPoints from the balance.
-- Everything runs in one transaction under the client's rewards lock (the
-- one sp_posRewardRedemptions_redeem takes), so concurrent sales can't spend
-- the same points or stamps. The reward is redeemed here, linked to the sale
-- (posRewardRedemptions.incomeId; a filtered unique index allows one applied
-- reward per sale). Anything not applicable is returned in "rejected" and
-- does not change the total. Idempotent per sale: a sale with a redemption
-- or a coupon already stamped is returned as is.
--
-- Also writes incomeDetails.netAmount (net paid per line) for the points
-- earned on the sale (2026-10-18b, earn as a % of what was paid).
--
-- Output:
--   { "result": [{ "incomeId", "subtotal", "total", "discountAmount",
--       "promotionCode", "applied": [{ catalogItemId, rewardType, discount }],
--       "rejected": [{ catalogItemId?, code?, reason }] }] }
-- ============================================================
IF OBJECT_ID('dbo.sp_income_applyDiscounts', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_income_applyDiscounts;
GO
CREATE PROCEDURE [dbo].[sp_income_applyDiscounts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId  INT         = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.incomeDiscounts[0].companyId'));
        DECLARE @incomeId   INT         = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.incomeDiscounts[0].incomeId'));
        DECLARE @userId     INT         = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.incomeDiscounts[0].userId'));
        DECLARE @couponCode VARCHAR(30) = NULLIF(UPPER(LTRIM(RTRIM(JSON_VALUE(@pjsonfile, '$.incomeDiscounts[0].couponCode')))), '');
        DECLARE @nowUtc     DATETIME2   = SYSUTCDATETIME();

        IF @companyId IS NULL OR @incomeId IS NULL
        BEGIN
            SELECT '{"error":"companyId and incomeId are required"}' AS jsonResult;
            RETURN;
        END

        DECLARE @clientId INT = (SELECT clientId FROM [dbo].[income] WHERE incomeId = @incomeId AND companyId = @companyId);
        IF @clientId IS NULL
        BEGIN
            SELECT '{"error":"incomeId not found for company"}' AS jsonResult;
            RETURN;
        END
        DECLARE @isClient BIT = CASE WHEN @clientId <> 1 THEN 1 ELSE 0 END; -- 1 = walk-in

        DECLARE @rejected TABLE (catalogItemId INT NULL, code VARCHAR(30) NULL, reason VARCHAR(40));
        DECLARE @applied  TABLE (catalogItemId INT, rewardType NVARCHAR(20), discount DECIMAL(12,2));
        DECLARE @lines    TABLE (incomeDetailId INT PRIMARY KEY, productId INT, qty INT, lineTotal DECIMAL(12,2), payQty INT);

        BEGIN TRAN;
        IF @isClient = 1
        BEGIN
            DECLARE @lockName NVARCHAR(255) = CONCAT(N'posRewards:', @companyId, N':', @clientId);
            EXEC sp_getapplock @Resource = @lockName, @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000;
        END

        DECLARE @oldTotal DECIMAL(10,2), @paymentMethod VARCHAR(50), @cashPaid DECIMAL(10,2), @stampedCode VARCHAR(30);
        SELECT @oldTotal = total, @paymentMethod = paymentMethod, @cashPaid = cashPaid, @stampedCode = promotionCode
        FROM [dbo].[income] WITH (UPDLOCK) WHERE incomeId = @incomeId;

        IF @stampedCode IS NOT NULL OR EXISTS (SELECT 1 FROM [dbo].[posRewardRedemptions] WHERE incomeId = @incomeId)
        BEGIN
            COMMIT;
            SELECT (SELECT @incomeId AS incomeId, i.total, i.discountAmount, i.promotionCode,
                           CAST(1 AS BIT) AS alreadyApplied
                    FROM [dbo].[income] i WHERE i.incomeId = @incomeId
                    FOR JSON PATH, ROOT('result')) AS jsonResult;
            RETURN;
        END

        INSERT INTO @lines (incomeDetailId, productId, qty, lineTotal, payQty)
        SELECT d.incomeDetailId, d.productId, CAST(ISNULL(d.quantity, 1) AS INT),
               CAST(ISNULL((SELECT SUM(CAST(c.price AS DECIMAL(10,2)) * ISNULL(ido.quantity, 1))
                            FROM [dbo].[incomeDetailOptions] ido
                            JOIN [dbo].[productOptionChoices] c ON c.productOptionChoiceId = ido.productOptionChoiceId
                            WHERE ido.incomeDetailId = d.incomeDetailId), 0) AS DECIMAL(12,2)),
               CAST(ISNULL(d.quantity, 1) AS INT)
        FROM [dbo].[incomeDetails] d
        WHERE d.incomeId = @incomeId;

        DECLARE @subtotal DECIMAL(12,2) = (SELECT ISNULL(SUM(lineTotal), 0) FROM @lines);

        -- ── Coupon ──
        DECLARE @couponId INT = NULL, @couponProductId INT, @firstOnly BIT;
        IF @couponCode IS NOT NULL
        BEGIN
            SELECT TOP 1 @couponId = catalogItemId, @couponProductId = freeProductId, @firstOnly = firstPurchaseOnly
            FROM [dbo].[posRewardCatalogItems]
            WHERE companyId = @companyId AND code = @couponCode AND rewardType = 'coupon_b2g1' AND isActive = 1
              AND (startAtUtc IS NULL OR startAtUtc <= @nowUtc)
              AND (endAtUtc   IS NULL OR endAtUtc   >= @nowUtc);

            IF @couponId IS NULL
                INSERT INTO @rejected (code, reason) VALUES (@couponCode, 'invalid_or_inactive');
            ELSE IF @subtotal <= 0
                INSERT INTO @rejected (catalogItemId, code, reason) VALUES (@couponId, @couponCode, 'no_line_prices');
            ELSE IF @firstOnly = 1 AND @isClient = 0
                INSERT INTO @rejected (catalogItemId, code, reason) VALUES (@couponId, @couponCode, 'needs_client');
            ELSE IF @firstOnly = 1 AND EXISTS (
                    SELECT 1 FROM [dbo].[income]
                    WHERE companyId = @companyId AND clientId = @clientId AND incomeId <> @incomeId)
                INSERT INTO @rejected (catalogItemId, code, reason) VALUES (@couponId, @couponCode, 'not_first_purchase');
            ELSE IF NOT EXISTS (SELECT 1 FROM @lines WHERE qty > 1 AND (@couponProductId IS NULL OR productId = @couponProductId))
                INSERT INTO @rejected (catalogItemId, code, reason) VALUES (@couponId, @couponCode, 'no_eligible_lines');
            ELSE
            BEGIN
                UPDATE @lines SET payQty = qty - qty / 2
                WHERE qty > 0 AND (@couponProductId IS NULL OR productId = @couponProductId);
                INSERT INTO @applied (catalogItemId, rewardType, discount)
                SELECT @couponId, 'coupon_b2g1', ISNULL(SUM(lineTotal - ROUND(lineTotal * (qty - qty / 2) / qty, 2)), 0)
                FROM @lines WHERE qty > 0 AND (@couponProductId IS NULL OR productId = @couponProductId);
            END
            IF NOT EXISTS (SELECT 1 FROM @applied WHERE catalogItemId = @couponId) SET @couponId = NULL;
        END

        -- ── Reward (one per sale) ──
        DECLARE @rewardIds TABLE (seq INT IDENTITY, catalogItemId INT);
        INSERT INTO @rewardIds (catalogItemId)
        SELECT TRY_CONVERT(INT, value) FROM OPENJSON(@pjsonfile, '$.incomeDiscounts[0].rewardCatalogItemIds')
        WHERE TRY_CONVERT(INT, value) IS NOT NULL;
        INSERT INTO @rejected (catalogItemId, reason) SELECT catalogItemId, 'one_reward_per_sale' FROM @rewardIds WHERE seq > 1;

        DECLARE @rewardId INT = (SELECT catalogItemId FROM @rewardIds WHERE seq = 1);
        DECLARE @rewardType NVARCHAR(20), @requiredPoints DECIMAL(12,2), @discountValue DECIMAL(12,2),
                @freeProductId INT, @freeLine INT, @redeemReward BIT = 0;
        IF @rewardId IS NOT NULL
        BEGIN
            SELECT @rewardType = rewardType, @requiredPoints = requiredPoints, @discountValue = discountValue,
                   @freeProductId = freeProductId
            FROM [dbo].[posRewardCatalogItems]
            WHERE catalogItemId = @rewardId AND companyId = @companyId AND isActive = 1
              AND (startAtUtc IS NULL OR startAtUtc <= @nowUtc)
              AND (endAtUtc   IS NULL OR endAtUtc   >= @nowUtc);

            IF @rewardType IS NULL OR @rewardType = 'coupon_b2g1'
                INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'invalid_or_inactive');
            ELSE IF @isClient = 0
                INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'needs_client');
            ELSE IF @rewardType = 'free_product'
            BEGIN
                SET @freeLine = (SELECT TOP 1 incomeDetailId FROM @lines
                                 WHERE productId = @freeProductId AND payQty >= 1 ORDER BY incomeDetailId);
                IF @freeLine IS NULL
                    INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'product_not_in_sale');
                ELSE IF @subtotal <= 0
                    INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'no_line_prices');
                ELSE IF NOT EXISTS (SELECT 1 FROM [dbo].[fn_posRewardStampStatus](@companyId, @clientId, @incomeId)
                                    WHERE catalogItemId = @rewardId AND unitsAvailable >= requiredUnits)
                    INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'insufficient_product_units');
                ELSE
                BEGIN
                    UPDATE @lines SET payQty = payQty - 1 WHERE incomeDetailId = @freeLine;
                    SET @redeemReward = 1;
                END
            END
            ELSE -- discount_fixed / discount_pct: debited below, only if the balance still covers it
                SET @redeemReward = 1;
        END

        -- ── Points debit: atomic, never below zero ──
        DECLARE @pointsSpent DECIMAL(12,2) = 0, @newBalance DECIMAL(12,2);
        IF @redeemReward = 1 AND @rewardType IN ('discount_fixed', 'discount_pct')
        BEGIN
            UPDATE [dbo].[posRewardBalances]
            SET balance = balance - @requiredPoints, lifetimeRedeemed = lifetimeRedeemed + @requiredPoints,
                lastActivity = GETUTCDATE(), @newBalance = balance - @requiredPoints
            WHERE companyId = @companyId AND clientId = @clientId AND balance >= @requiredPoints;
            IF @@ROWCOUNT = 0
            BEGIN
                INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'insufficient_points');
                SET @redeemReward = 0;
            END
            ELSE
                SET @pointsSpent = @requiredPoints;
        END

        IF @couponId IS NULL AND @redeemReward = 0
        BEGIN
            COMMIT;
            SELECT (SELECT @incomeId AS incomeId, @subtotal AS subtotal, @oldTotal AS total, CAST(0 AS DECIMAL(12,2)) AS discountAmount,
                           CAST(NULL AS VARCHAR(30)) AS promotionCode,
                           JSON_QUERY('[]') AS applied,
                           JSON_QUERY(ISNULL((SELECT catalogItemId, code, reason FROM @rejected FOR JSON PATH), '[]')) AS rejected
                    FOR JSON PATH, ROOT('result'), INCLUDE_NULL_VALUES) AS jsonResult;
            RETURN;
        END

        -- ── New total ──
        DECLARE @lineTotal DECIMAL(12,2) = (
            SELECT ISNULL(SUM(CASE WHEN qty > 0 AND payQty < qty THEN ROUND(lineTotal * payQty / qty, 2) ELSE lineTotal END), 0)
            FROM @lines);
        -- No line prices: discounts come off the total as charged.
        DECLARE @base DECIMAL(12,2) = CASE WHEN @subtotal > 0 THEN @lineTotal ELSE @oldTotal END;
        DECLARE @gross DECIMAL(12,2) = CASE WHEN @subtotal > 0 THEN @subtotal ELSE @oldTotal END;
        DECLARE @pointsDiscount DECIMAL(12,2) = 0;
        IF @pointsSpent > 0
            SET @pointsDiscount = CASE WHEN @rewardType = 'discount_fixed'
                                       THEN CASE WHEN @discountValue < @base THEN @discountValue ELSE @base END
                                       ELSE ROUND(@base * @discountValue / 100, 2) END;
        DECLARE @newTotal DECIMAL(12,2) = @base - @pointsDiscount;
        IF @newTotal < 0 SET @newTotal = 0;
        DECLARE @discountAmount DECIMAL(12,2) = CASE WHEN @gross > @newTotal THEN @gross - @newTotal ELSE 0 END;
        DECLARE @cashReturn DECIMAL(10,2) = CASE WHEN ISNULL(@cashPaid, 0) > @newTotal THEN ISNULL(@cashPaid, 0) - @newTotal ELSE 0 END;
        DECLARE @isCash BIT = CASE WHEN LOWER(@paymentMethod) IN ('cash', 'efectivo') THEN 1 ELSE 0 END;

        IF @redeemReward = 1
        BEGIN
            INSERT INTO [dbo].[posRewardRedemptions]
                (companyId, clientId, catalogItemId, pointsSpent, status, incomeId, redeemedByUserId)
            VALUES (@companyId, @clientId, @rewardId, @pointsSpent, 'applied', @incomeId, ISNULL(@userId, 0));
            DECLARE @redemptionId INT = SCOPE_IDENTITY();

            IF @pointsSpent > 0
                INSERT INTO [dbo].[posRewardTransactions]
                    (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
                VALUES (@companyId, @clientId, 'REDEEM', 'D', @pointsSpent, 'redemption', @redemptionId, @newBalance,
                        CONCAT('Canje #', @redemptionId, ' en venta #', @incomeId));

            INSERT INTO @applied (catalogItemId, rewardType, discount)
            VALUES (@rewardId, @rewardType,
                    CASE WHEN @rewardType = 'free_product'
                         THEN (SELECT ROUND(lineTotal / NULLIF(qty, 0), 2) FROM @lines WHERE incomeDetailId = @freeLine)
                         ELSE @pointsDiscount END);
        END

        UPDATE [dbo].[income] SET
            total          = @newTotal,
            discountAmount = @discountAmount,
            promotionId    = CASE WHEN @couponId IS NOT NULL THEN @couponId ELSE promotionId END,
            promotionCode  = CASE WHEN @couponId IS NOT NULL THEN @couponCode ELSE promotionCode END,
            cashReturn     = CASE WHEN @isCash = 1 THEN @cashReturn ELSE cashReturn END
        WHERE incomeId = @incomeId;

        -- Net paid per line (after the coupon, the free unit and a share of the
        -- points discount): what sp_posRewardTransactions_earnFromTicket earns
        -- on for companies with posRewardSettings.earnPct.
        IF @subtotal > 0
            UPDATE d SET netAmount = CASE WHEN @lineTotal > 0
                                          THEN lv.paid - ROUND(@pointsDiscount * lv.paid / @lineTotal, 2)
                                          ELSE 0 END
            FROM [dbo].[incomeDetails] d
            JOIN (SELECT incomeDetailId,
                         CASE WHEN qty > 0 AND payQty < qty THEN ROUND(lineTotal * payQty / qty, 2) ELSE lineTotal END AS paid
                  FROM @lines) lv ON lv.incomeDetailId = d.incomeDetailId;

        UPDATE [dbo].[cashRegisterMovements] SET
            amount     = @newTotal,
            cashReturn = CASE WHEN @isCash = 1 THEN @cashReturn ELSE cashReturn END
        WHERE incomeId = @incomeId;

        COMMIT;

        SELECT (SELECT @incomeId AS incomeId, @subtotal AS subtotal, @newTotal AS total, @discountAmount AS discountAmount,
                       CASE WHEN @couponId IS NOT NULL THEN @couponCode END AS promotionCode,
                       JSON_QUERY(ISNULL((SELECT catalogItemId, rewardType, discount FROM @applied FOR JSON PATH), '[]')) AS applied,
                       JSON_QUERY(ISNULL((SELECT catalogItemId, code, reason FROM @rejected FOR JSON PATH), '[]')) AS rejected
                FOR JSON PATH, ROOT('result'), INCLUDE_NULL_VALUES) AS jsonResult;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
