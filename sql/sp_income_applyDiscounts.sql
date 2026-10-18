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
--   coupon_b2g1   pay qty - qty/2 (2x1) on lines of freeProductId, or all
--                 lines when NULL. firstPurchaseOnly = the client never earned
--                 POS points (the POS front's "first purchase" rule) and never
--                 used this coupon. Runs before this sale's points are earned.
--   free_product  one unit of freeProductId free, if units bought BEFORE this
--                 sale minus earlier redemptions of the item >= requiredUnits.
--   discount_*    $/% off the discounted total; debits the points balance.
-- The reward is redeemed here, linked to the sale (posRewardRedemptions.incomeId),
-- so a sale that never happened can't consume it. Anything not applicable
-- is returned in "rejected" and does not change the total.
-- Idempotent per sale: a sale with a redemption or a coupon already stamped
-- is returned as is.
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

        DECLARE @clientId INT, @oldTotal DECIMAL(10,2), @paymentMethod VARCHAR(50), @cashPaid DECIMAL(10,2),
                @stampedCode VARCHAR(30);
        SELECT @clientId = clientId, @oldTotal = total, @paymentMethod = paymentMethod, @cashPaid = cashPaid,
               @stampedCode = promotionCode
        FROM [dbo].[income] WHERE incomeId = @incomeId AND companyId = @companyId;

        IF @oldTotal IS NULL
        BEGIN
            SELECT '{"error":"incomeId not found for company"}' AS jsonResult;
            RETURN;
        END

        DECLARE @rejected TABLE (catalogItemId INT NULL, code VARCHAR(30) NULL, reason VARCHAR(40));
        DECLARE @applied  TABLE (catalogItemId INT, rewardType NVARCHAR(20), discount DECIMAL(12,2));

        IF @stampedCode IS NOT NULL OR EXISTS (SELECT 1 FROM [dbo].[posRewardRedemptions] WHERE incomeId = @incomeId)
        BEGIN
            SELECT (SELECT @incomeId AS incomeId, @oldTotal AS total, i.discountAmount, i.promotionCode,
                           CAST(1 AS BIT) AS alreadyApplied
                    FROM [dbo].[income] i WHERE i.incomeId = @incomeId
                    FOR JSON PATH, ROOT('result')) AS jsonResult;
            RETURN;
        END

        DECLARE @lines TABLE (incomeDetailId INT PRIMARY KEY, productId INT, qty INT, lineTotal DECIMAL(12,2), payQty INT);
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
        DECLARE @isClient BIT = CASE WHEN @clientId IS NOT NULL AND @clientId <> 1 THEN 1 ELSE 0 END; -- 1 = walk-in

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
            ELSE IF @firstOnly = 1 AND (
                    EXISTS (SELECT 1 FROM [dbo].[posRewardBalances]
                            WHERE companyId = @companyId AND clientId = @clientId AND lifetimeEarned > 0)
                    OR EXISTS (SELECT 1 FROM [dbo].[income]
                               WHERE companyId = @companyId AND clientId = @clientId AND promotionId = @couponId AND incomeId <> @incomeId))
                INSERT INTO @rejected (catalogItemId, code, reason) VALUES (@couponId, @couponCode, 'not_first_purchase');
            ELSE IF NOT EXISTS (SELECT 1 FROM @lines WHERE qty > 1 AND (@couponProductId IS NULL OR productId = @couponProductId))
                INSERT INTO @rejected (catalogItemId, code, reason) VALUES (@couponId, @couponCode, 'no_eligible_lines');
            ELSE
            BEGIN
                UPDATE @lines SET payQty = qty - qty / 2
                WHERE qty > 0 AND (@couponProductId IS NULL OR productId = @couponProductId);
                INSERT INTO @applied (catalogItemId, rewardType, discount) VALUES (@couponId, 'coupon_b2g1', 0);
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
        DECLARE @rewardType NVARCHAR(20), @requiredPoints DECIMAL(12,2), @requiredUnits DECIMAL(12,2),
                @discountValue DECIMAL(12,2), @freeProductId INT, @pointsDiscount DECIMAL(12,2) = 0, @redeemReward BIT = 0;
        IF @rewardId IS NOT NULL
        BEGIN
            SELECT @rewardType = c.rewardType, @requiredPoints = c.requiredPoints, @discountValue = c.discountValue,
                   @freeProductId = c.freeProductId,
                   @requiredUnits = COALESCE(c.requiredUnits,
                       CASE WHEN ISNULL(r.pointsPerUnit, 0) > 0 THEN c.requiredPoints / r.pointsPerUnit ELSE c.requiredPoints END)
            FROM [dbo].[posRewardCatalogItems] c
            OUTER APPLY (SELECT TOP 1 pr.pointsPerUnit FROM [dbo].[posRewardProductRates] pr
                         WHERE pr.companyId = c.companyId AND pr.productId = c.freeProductId AND pr.isActive = 1) r
            WHERE c.catalogItemId = @rewardId AND c.companyId = @companyId AND c.isActive = 1
              AND (c.startAtUtc IS NULL OR c.startAtUtc <= @nowUtc)
              AND (c.endAtUtc   IS NULL OR c.endAtUtc   >= @nowUtc);

            IF @rewardType IS NULL OR @rewardType = 'coupon_b2g1'
                INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'invalid_or_inactive');
            ELSE IF @isClient = 0
                INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'needs_client');
            ELSE IF @rewardType = 'free_product'
            BEGIN
                -- Same unit check as sp_posRewardRedemptions_redeem, counting
                -- only purchases before this sale (the free unit is in it).
                DECLARE @unitsBought DECIMAL(12,2) = ISNULL((
                    SELECT SUM(d.quantity) FROM [dbo].[incomeDetails] d
                    JOIN [dbo].[income] i ON i.incomeId = d.incomeId
                    WHERE d.productId = @freeProductId AND i.clientId = @clientId AND i.companyId = @companyId
                      AND i.incomeId <> @incomeId), 0);
                DECLARE @priorRedemptions INT = (
                    SELECT COUNT(*) FROM [dbo].[posRewardRedemptions]
                    WHERE companyId = @companyId AND clientId = @clientId AND catalogItemId = @rewardId AND status = 'applied');
                DECLARE @freeLine INT = (SELECT TOP 1 incomeDetailId FROM @lines
                                         WHERE productId = @freeProductId AND payQty >= 1 ORDER BY incomeDetailId);

                IF @freeLine IS NULL
                    INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'product_not_in_sale');
                ELSE IF @subtotal <= 0
                    INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'no_line_prices');
                ELSE IF @unitsBought - @priorRedemptions * @requiredUnits < @requiredUnits
                    INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'insufficient_product_units');
                ELSE
                BEGIN
                    UPDATE @lines SET payQty = payQty - 1 WHERE incomeDetailId = @freeLine;
                    SET @redeemReward = 1;
                END
            END
            ELSE -- discount_fixed / discount_pct
            BEGIN
                DECLARE @balance DECIMAL(12,2) = ISNULL((SELECT balance FROM [dbo].[posRewardBalances]
                                                         WHERE companyId = @companyId AND clientId = @clientId), 0);
                IF @balance < @requiredPoints
                    INSERT INTO @rejected (catalogItemId, reason) VALUES (@rewardId, 'insufficient_points');
                ELSE
                    SET @redeemReward = 1;
            END
        END

        -- ── New total ──
        DECLARE @lineTotal DECIMAL(12,2) = (
            SELECT ISNULL(SUM(CASE WHEN qty > 0 AND payQty < qty THEN ROUND(lineTotal * payQty / qty, 2) ELSE lineTotal END), 0)
            FROM @lines);
        IF @redeemReward = 1 AND @rewardType IN ('discount_fixed', 'discount_pct')
        BEGIN
            -- No line prices: the points discount comes off the total as charged.
            DECLARE @base DECIMAL(12,2) = CASE WHEN @subtotal > 0 THEN @lineTotal ELSE @oldTotal END;
            SET @pointsDiscount = CASE WHEN @rewardType = 'discount_fixed'
                                       THEN CASE WHEN @discountValue < @base THEN @discountValue ELSE @base END
                                       ELSE ROUND(@base * @discountValue / 100, 2) END;
        END

        IF @couponId IS NULL AND @redeemReward = 0
        BEGIN
            SELECT (SELECT @incomeId AS incomeId, @subtotal AS subtotal, @oldTotal AS total, CAST(0 AS DECIMAL(12,2)) AS discountAmount,
                           CAST(NULL AS VARCHAR(30)) AS promotionCode,
                           JSON_QUERY('[]') AS applied,
                           JSON_QUERY(ISNULL((SELECT catalogItemId, code, reason FROM @rejected FOR JSON PATH), '[]')) AS rejected
                    FOR JSON PATH, ROOT('result'), INCLUDE_NULL_VALUES) AS jsonResult;
            RETURN;
        END

        DECLARE @gross DECIMAL(12,2) = CASE WHEN @subtotal > 0 THEN @subtotal ELSE @oldTotal END;
        DECLARE @newTotal DECIMAL(12,2) = (CASE WHEN @subtotal > 0 THEN @lineTotal ELSE @oldTotal END) - @pointsDiscount;
        IF @newTotal < 0 SET @newTotal = 0;
        DECLARE @discountAmount DECIMAL(12,2) = CASE WHEN @gross > @newTotal THEN @gross - @newTotal ELSE 0 END;
        DECLARE @cashReturn DECIMAL(10,2) = CASE WHEN ISNULL(@cashPaid, 0) > @newTotal THEN ISNULL(@cashPaid, 0) - @newTotal ELSE 0 END;
        DECLARE @isCash BIT = CASE WHEN LOWER(@paymentMethod) IN ('cash', 'efectivo') THEN 1 ELSE 0 END;

        IF @couponId IS NOT NULL
            UPDATE @applied SET discount = (
                SELECT ISNULL(SUM(lineTotal - ROUND(lineTotal * (qty - qty / 2) / qty, 2)), 0)
                FROM @lines WHERE qty > 0 AND (@couponProductId IS NULL OR productId = @couponProductId))
            WHERE catalogItemId = @couponId;

        BEGIN TRAN;

        IF @redeemReward = 1
        BEGIN
            DECLARE @pointsSpent DECIMAL(12,2) = CASE WHEN @rewardType = 'free_product' THEN 0 ELSE @requiredPoints END;
            INSERT INTO [dbo].[posRewardRedemptions]
                (companyId, clientId, catalogItemId, pointsSpent, status, incomeId, redeemedByUserId)
            VALUES (@companyId, @clientId, @rewardId, @pointsSpent, 'applied', @incomeId, ISNULL(@userId, 0));
            DECLARE @redemptionId INT = SCOPE_IDENTITY();

            IF @pointsSpent > 0
            BEGIN
                DECLARE @negPoints DECIMAL(12,2) = -@pointsSpent, @newBalance DECIMAL(12,2);
                EXEC [dbo].[sp_posRewardBalances_applyDelta]
                    @companyId = @companyId, @clientId = @clientId,
                    @pointsDelta = @negPoints, @earnedDelta = 0, @redeemedDelta = @pointsSpent,
                    @newBalance = @newBalance OUTPUT;
                INSERT INTO [dbo].[posRewardTransactions]
                    (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
                VALUES (@companyId, @clientId, 'REDEEM', 'D', @pointsSpent, 'redemption', @redemptionId, @newBalance,
                        CONCAT('Canje #', @redemptionId, ' en venta #', @incomeId));
            END

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
