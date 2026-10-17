-- ============================================================
-- 2026-10-16b: sp_income's B2G1 engine respects dbo.promotion_targets.
--
-- Before: sp_income discounted EVERY sale line for any active B2G1 code,
-- ignoring promotion_targets (only sp_income_apply_promo read them). Also, if
-- the lines' option prices summed to 0, it overwrote the sale total with 0.
--
-- After:
--   * a line is discounted only if the promotion has an 'ALL' target or a
--     'PRODUCT' target for that line's productId;
--   * lines that aren't eligible keep their full price in the new total;
--   * the promotion is not applied (total left as sent) when no line is
--     eligible or the line prices sum to 0.
-- For an 'ALL' promotion (the seeded 2X1) the result is unchanged.
--
-- sp_income only exists in the repo as the 2026-08-15 snapshot, so instead of
-- re-creating it from a possibly stale copy this PATCHES the live definition
-- in place: four single-line replacements, each required to match exactly
-- once (binary collation), else the migration fails and nothing changes.
-- Safe to re-run: skipped once the definition already has isEligible.
-- ============================================================

-- Promotions created without targets (sp_promotions before today) would stop
-- applying under the stricter rule: give them the 'ALL' they implicitly had.
INSERT INTO [dbo].[promotion_targets] (promotionId, targetType, productId)
SELECT p.promotionId, 'ALL', NULL
FROM [dbo].[promotions] p
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[promotion_targets] t WHERE t.promotionId = p.promotionId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_promotion_targets_promotion' AND object_id = OBJECT_ID('dbo.promotion_targets'))
    CREATE INDEX IX_promotion_targets_promotion ON [dbo].[promotion_targets] (promotionId, targetType, productId);
GO

DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID('dbo.sp_income'));
IF @def IS NULL
    RAISERROR('sp_income not found', 16, 1);
ELSE IF CHARINDEX(N'AS isEligible', @def COLLATE Latin1_General_BIN) > 0
    PRINT 'sp_income already respects promotion_targets; skipped.';
ELSE
BEGIN
    DECLARE @patches TABLE (seq INT, anchor NVARCHAR(400), replacement NVARCHAR(1000));
    INSERT INTO @patches VALUES
    -- EligibleDetails: flag each line the promotion targets.
    (1, N'CAST(ISNULL(d.quantity,1) AS INT) AS qty',
        N'CAST(ISNULL(d.quantity,1) AS INT) AS qty, CASE WHEN EXISTS (SELECT 1 FROM dbo.promotion_targets pt WHERE pt.promotionId = @promotionId AND (pt.targetType = ''ALL'' OR (pt.targetType = ''PRODUCT'' AND pt.productId = d.productId))) THEN 1 ELSE 0 END AS isEligible'),
    -- LineTotals: carry the flag.
    (2, N'e.incomeDetailId,',
        N'e.incomeDetailId, e.isEligible,'),
    -- PromoTotals: carry the flag.
    (3, N'lineTotal,',
        N'lineTotal, isEligible,'),
    -- New total: discounted price on eligible lines, full price on the rest;
    -- NULL (promo not applied) when nothing is eligible or prices sum to 0.
    (4, N'@newTotal = CAST(ISNULL(SUM(promoLineTotal),0) AS DECIMAL(10,2))',
        N'@newTotal = CASE WHEN MAX(isEligible) = 1 AND SUM(lineTotal) > 0 THEN CAST(SUM(CASE WHEN isEligible = 1 THEN promoLineTotal ELSE lineTotal END) AS DECIMAL(10,2)) END');

    DECLARE @seq INT = 1, @anchor NVARCHAR(400), @replacement NVARCHAR(1000), @hits INT, @msg NVARCHAR(600);
    WHILE @seq <= 4
    BEGIN
        SELECT @anchor = anchor, @replacement = replacement FROM @patches WHERE seq = @seq;
        SET @hits = (DATALENGTH(@def) - DATALENGTH(REPLACE(@def COLLATE Latin1_General_BIN, @anchor, N''))) / DATALENGTH(@anchor);
        IF @hits <> 1
        BEGIN
            SET @msg = CONCAT(N'sp_income patch ', @seq, N': expected 1 match of "', @anchor, N'", found ', @hits, N'. Nothing changed.');
            RAISERROR(@msg, 16, 1);
            RETURN;
        END
        SET @def = REPLACE(@def COLLATE Latin1_General_BIN, @anchor, @replacement);
        SET @seq += 1;
    END

    DECLARE @createAt INT = CHARINDEX(N'CREATE', @def COLLATE Latin1_General_BIN);
    IF @createAt = 0 OR SUBSTRING(@def, @createAt, 60) NOT LIKE N'CREATE%PROC%sp_income%'
    BEGIN
        RAISERROR('sp_income definition does not start with CREATE PROC; nothing changed.', 16, 1);
        RETURN;
    END
    SET @def = STUFF(@def, @createAt, 6, N'ALTER');
    EXEC sp_executesql @def;
    PRINT 'sp_income now respects promotion_targets.';
END
GO
