-- =============================================================================
-- Phase 1 — inventory: dbo.inventoryStock + dbo.inventoryMovements are the ONLY stock
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-15b_products_by_company_category_filter.sql (redeploys that SP) and
-- 2026-10-02b_expense_item_quantity_cost_supplies.sql (needs expenseDetails.quantity).
--
-- WHY: stock lived in two places that never agreed — productDetails.stockQuantity
--   (typed in the product wizard) and inventoryStock/inventoryMovements (a proper
--   ledger, but sp_inventory_adjust had no caller). Neither moved on a sale or a
--   purchase, so no stock number in the app was ever right.
--
-- WHAT:
--   1. products.trackInventory BIT (default 0). First run marks as tracked every
--      physical good: isSupply = 1, has a barcode, has productDetails stock <> 0,
--      or already has an inventoryStock row. Made-to-order food stays 0 (never
--      decremented). Flip it per product with sp_products_save "trackInventory".
--   2. Opening balance: tracked products without an inventoryStock row get one,
--      with the stock of their first productDetails row, plus an 'opening'
--      movement (refType 'productDetails'). Existing inventoryStock rows are kept.
--   3. dbo.sp_inventory_post — one movement + balance update, no result set.
--   4. Triggers post movements automatically, for every code path (sp_income,
--      sp_expense, cascaded deletes, future SPs):
--        incomeDetails  insert → 'sale' (−qty)      delete → 'sale_reversal' (+qty)
--        expenseDetails insert → 'purchase' (+qty)  delete → 'purchase_reversal' (−qty)
--      An edited line posts the difference. Reversals only happen for lines this
--      ledger posted, so deleting a sale made BEFORE this migration does not add
--      phantom stock. Untracked products are ignored. Stock may go negative (the
--      sale is never blocked); the negative number is the signal to recount.
--   5. sp_products_save: productDetails keeps prices only (its stockQuantity is
--      frozen); the stock typed in the wizard is posted as 'opening'/'adjustment'
--      for the difference. sp_products_by_company / sp_products_one read stock
--      from inventoryStock (same JSON shape + top-level stockQuantity, trackInventory).
--   6. Verify result sets.
-- ROLLBACK: 2026-10-15c_inventory_single_source_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- 0) Pre-checks -------------------------------------------------------------------
IF OBJECT_ID('dbo.inventoryStock', 'U') IS NULL OR OBJECT_ID('dbo.inventoryMovements', 'U') IS NULL
    BEGIN RAISERROR('dbo.inventoryStock / dbo.inventoryMovements missing.', 16, 1); SET NOEXEC ON; RETURN; END
IF COL_LENGTH('dbo.expenseDetails', 'quantity') IS NULL
    BEGIN RAISERROR('expenseDetails.quantity missing — run 2026-10-02b_expense_item_quantity_cost_supplies.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
IF COL_LENGTH('dbo.products', 'productCategoryId') IS NULL
    BEGIN RAISERROR('products.productCategoryId missing — run 2026-10-15_products_productCategoryId.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
GO

-- 1) products.trackInventory (+ first-run backfill) -----------------------------------
IF COL_LENGTH('dbo.products', 'trackInventory') IS NULL
BEGIN
    ALTER TABLE dbo.products ADD trackInventory BIT NOT NULL
        CONSTRAINT DF_products_trackInventory DEFAULT (0);

    -- Dynamic SQL: the new column is only visible once the ALTER above has run.
    EXEC (N'
        UPDATE p SET trackInventory = 1
        FROM dbo.products p
        WHERE ISNULL(p.isSupply, 0) = 1
           OR NULLIF(LTRIM(RTRIM(p.barCode)), '''') IS NOT NULL
           OR EXISTS (SELECT 1 FROM dbo.productDetails d WHERE d.productId = p.productId AND d.stockQuantity <> 0)
           OR EXISTS (SELECT 1 FROM dbo.inventoryStock s WHERE s.productId = p.productId);');
END
RAISERROR('OK: products.trackInventory', 0, 1) WITH NOWAIT;
GO

-- Lookup used by the triggers ("did this ledger post that ticket line?")
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_inventoryMovements_ref'
               AND object_id = OBJECT_ID('dbo.inventoryMovements'))
    CREATE NONCLUSTERED INDEX IX_inventoryMovements_ref
        ON dbo.inventoryMovements (refType, refId, productId);
GO

-- 2) Opening balances from productDetails --------------------------------------------
IF OBJECT_ID('tempdb..#opening') IS NOT NULL DROP TABLE #opening;

;WITH firstDetail AS (
    SELECT d.productId, d.productDetailId, d.stockQuantity,
           ROW_NUMBER() OVER (PARTITION BY d.productId ORDER BY d.productDetailId) AS rn
    FROM dbo.productDetails d
)
SELECT p.companyId, p.productId, fd.productDetailId,
       CAST(fd.stockQuantity AS DECIMAL(18,3)) AS qty
INTO #opening
FROM dbo.products p
JOIN firstDetail fd ON fd.productId = p.productId AND fd.rn = 1
WHERE p.trackInventory = 1
  AND NOT EXISTS (SELECT 1 FROM dbo.inventoryStock s
                  WHERE s.companyId = p.companyId AND s.productId = p.productId);

SET XACT_ABORT ON;
BEGIN TRANSACTION;

INSERT INTO dbo.inventoryStock (companyId, productId, stockQuantity)
SELECT companyId, productId, qty FROM #opening;

INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
SELECT companyId, productId, qty, 'opening',
       N'Fase 1: saldo inicial tomado de productDetails.stockQuantity', 'productDetails', productDetailId, NULL
FROM #opening
WHERE qty <> 0;

COMMIT TRANSACTION;

SELECT COUNT(*) AS openingRowsCreated FROM #opening;
DROP TABLE #opening;
SET XACT_ABORT OFF;
GO

-- 3) dbo.sp_inventory_post -------------------------------------------------------------
CREATE OR ALTER PROC dbo.sp_inventory_post
    @companyId     INT,
    @productId     INT,
    @quantityDelta DECIMAL(18,3),
    @reason        VARCHAR(30),
    @refType       VARCHAR(30)   = NULL,
    @refId         INT           = NULL,
    @userId        INT           = NULL,
    @notes         NVARCHAR(300) = NULL
AS
BEGIN
    -- One ledger row + the balance, atomically. Returns nothing (safe to call from
    -- SPs whose caller reads the first result set).
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @companyId IS NULL OR @productId IS NULL OR @reason IS NULL
        THROW 50110, 'sp_inventory_post: companyId, productId and reason are required.', 1;
    IF ISNULL(@quantityDelta, 0) = 0 RETURN;

    BEGIN TRANSACTION;

    INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
    VALUES (@companyId, @productId, @quantityDelta, @reason, @notes, @refType, @refId, @userId);

    MERGE dbo.inventoryStock WITH (HOLDLOCK) AS t
    USING (SELECT @companyId AS companyId, @productId AS productId) AS s
       ON t.companyId = s.companyId AND t.productId = s.productId
    WHEN MATCHED THEN
        UPDATE SET stockQuantity = t.stockQuantity + @quantityDelta, updatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (companyId, productId, stockQuantity) VALUES (s.companyId, s.productId, @quantityDelta);

    COMMIT TRANSACTION;
END
GO

-- 4a) Sales trigger --------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_incomeDetails_inventory
ON dbo.incomeDetails
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    -- Posts sales to the inventory ledger. See the header of
    -- 2026-10-15c_inventory_single_source.sql for the rules.
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @m TABLE (
        companyId     INT           NOT NULL,
        productId     INT           NOT NULL,
        refId         INT           NOT NULL,
        quantityDelta DECIMAL(18,3) NOT NULL,
        userId        INT           NULL
    );

    ;WITH lines AS (
        -- New line: needs a tracked product.
        SELECT i.incomeId AS refId, i.productId, -CAST(i.quantity AS DECIMAL(18,3)) AS q, 1 AS needsTracking
        FROM inserted i
        WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.incomeDetailId = i.incomeDetailId)

        UNION ALL
        -- Deleted or edited line: undo only what this ledger posted for it.
        SELECT d.incomeId, d.productId, CAST(d.quantity AS DECIMAL(18,3)), 0
        FROM deleted d
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'income' AND m.refId = d.incomeId AND m.productId = d.productId)

        UNION ALL
        -- Edited line that was posted: post its new quantity.
        SELECT i.incomeId, i.productId, -CAST(i.quantity AS DECIMAL(18,3)), 0
        FROM inserted i
        JOIN deleted d ON d.incomeDetailId = i.incomeDetailId
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'income' AND m.refId = d.incomeId AND m.productId = d.productId)
    )
    INSERT INTO @m (companyId, productId, refId, quantityDelta, userId)
    SELECT COALESCE(h.companyId, p.companyId), l.productId, l.refId, SUM(l.q), MAX(h.userId)
    FROM lines l
    JOIN dbo.products p ON p.productId = l.productId
    LEFT JOIN dbo.income h ON h.incomeId = l.refId
    WHERE l.needsTracking = 0 OR p.trackInventory = 1
    GROUP BY COALESCE(h.companyId, p.companyId), l.productId, l.refId
    HAVING SUM(l.q) <> 0;

    IF NOT EXISTS (SELECT 1 FROM @m) RETURN;

    INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
    SELECT companyId, productId, quantityDelta,
           CASE WHEN quantityDelta < 0 THEN 'sale' ELSE 'sale_reversal' END,
           NULL, 'income', refId, userId
    FROM @m;

    MERGE dbo.inventoryStock WITH (HOLDLOCK) AS t
    USING (SELECT companyId, productId, SUM(quantityDelta) AS delta
           FROM @m GROUP BY companyId, productId) AS s
       ON t.companyId = s.companyId AND t.productId = s.productId
    WHEN MATCHED THEN
        UPDATE SET stockQuantity = t.stockQuantity + s.delta, updatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (companyId, productId, stockQuantity) VALUES (s.companyId, s.productId, s.delta);
END
GO

-- 4b) Purchases trigger --------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_expenseDetails_inventory
ON dbo.expenseDetails
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    -- Posts purchases to the inventory ledger. See the header of
    -- 2026-10-15c_inventory_single_source.sql for the rules.
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @m TABLE (
        companyId     INT           NOT NULL,
        productId     INT           NOT NULL,
        refId         INT           NOT NULL,
        quantityDelta DECIMAL(18,3) NOT NULL,
        userId        INT           NULL
    );

    ;WITH lines AS (
        -- New line: needs a tracked product.
        SELECT i.expenseId AS refId, i.productId, CAST(i.quantity AS DECIMAL(18,3)) AS q, 1 AS needsTracking
        FROM inserted i
        WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.expenseDetailId = i.expenseDetailId)

        UNION ALL
        -- Deleted or edited line: undo only what this ledger posted for it.
        SELECT d.expenseId, d.productId, -CAST(d.quantity AS DECIMAL(18,3)), 0
        FROM deleted d
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'expense' AND m.refId = d.expenseId AND m.productId = d.productId)

        UNION ALL
        -- Edited line that was posted: post its new quantity.
        SELECT i.expenseId, i.productId, CAST(i.quantity AS DECIMAL(18,3)), 0
        FROM inserted i
        JOIN deleted d ON d.expenseDetailId = i.expenseDetailId
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'expense' AND m.refId = d.expenseId AND m.productId = d.productId)
    )
    INSERT INTO @m (companyId, productId, refId, quantityDelta, userId)
    SELECT COALESCE(h.companyId, p.companyId), l.productId, l.refId, SUM(l.q), MAX(h.userId)
    FROM lines l
    JOIN dbo.products p ON p.productId = l.productId
    LEFT JOIN dbo.expenses h ON h.expenseId = l.refId
    WHERE l.needsTracking = 0 OR p.trackInventory = 1
    GROUP BY COALESCE(h.companyId, p.companyId), l.productId, l.refId
    HAVING SUM(l.q) <> 0;

    IF NOT EXISTS (SELECT 1 FROM @m) RETURN;

    INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
    SELECT companyId, productId, quantityDelta,
           CASE WHEN quantityDelta > 0 THEN 'purchase' ELSE 'purchase_reversal' END,
           NULL, 'expense', refId, userId
    FROM @m;

    MERGE dbo.inventoryStock WITH (HOLDLOCK) AS t
    USING (SELECT companyId, productId, SUM(quantityDelta) AS delta
           FROM @m GROUP BY companyId, productId) AS s
       ON t.companyId = s.companyId AND t.productId = s.productId
    WHEN MATCHED THEN
        UPDATE SET stockQuantity = t.stockQuantity + s.delta, updatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (companyId, productId, stockQuantity) VALUES (s.companyId, s.productId, s.delta);
END
GO

-- 5) Product SPs (stock from inventoryStock) -------------------------------------------

-- dbo.sp_products_by_company
CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'                         -- all
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1", "categoryId": "1002" } ] }'  -- one category
    */

    DECLARE @companyId INT;
    DECLARE @categoryId INT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    -- Optional: productCategoryId (or legacy "categoryId"); missing/0 = all categories.
    SELECT TOP (1)
        @categoryId = NULLIF(TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'),
                                               JSON_VALUE(value, '$.categoryId')) AS INT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.productCategoryId AS categoryId,
        ISNULL(p.code, '') AS code,
        ISNULL(p.barCode, '') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        p.trackInventory,
        -- Stock lives only in inventoryStock (phase 1); details[] keeps its shape.
        ISNULL(inv.stockQuantity, 0) AS stockQuantity,
        (
            SELECT d.productDetailId, ISNULL(inv.stockQuantity, 0) AS stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name
            FROM productCategories c
            WHERE c.productCategoryId = p.productCategoryId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )) AS category,
        (
            SELECT ds.productDescriptionId, ds.Dosage, ds.measurementId, ds.is_principal, ds.activeIngredientId
            FROM productsDescription ds
            WHERE ds.productId = p.productId
            FOR JSON PATH
        ) AS descriptions,
        (
            SELECT
                o.productOptionId AS [productOptionId],
                o.name,
                o.type,
                (
                    SELECT
                        c.productOptionChoiceId AS [productOptionChoiceId],
                        c.name,
                        c.price
                    FROM productOptionChoices c
                    WHERE c.productOptionId = o.productOptionId
                    FOR JSON PATH
                ) AS choices
            FROM productOptions o
            WHERE o.productId = p.productId
            FOR JSON PATH
        ) AS options
    FROM products p
    LEFT JOIN dbo.inventoryStock inv
        ON inv.companyId = p.companyId AND inv.productId = p.productId
    OUTER APPLY (
        SELECT TOP 1 x.salePrice
        FROM productDetails x
        WHERE x.productId = p.productId
        ORDER BY x.productDetailId
    ) pd
    WHERE p.companyId = @companyId
      AND ISNULL(p.isSupply, 0) = 0
      AND (@categoryId IS NULL OR p.productCategoryId = @categoryId)
    ORDER BY p.name
    FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_products_one
CREATE OR ALTER PROC [dbo].[sp_products_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
        "productId": "1"
        }
     ]   
    }'
    */

    DECLARE @productId INT;

    -- Extracting ProductId safely
    SET @productId = TRY_CAST((SELECT JSON_VALUE(value, '$.productId') FROM OPENJSON(@pjsonfile, '$.products')) AS INT);

    -- Complete JSON structure generation matching the layout used by your application
    SELECT 
        p.[productId]
        ,p.[name]
        ,ISNULL(p.[barCode],'') AS barCode
        ,ISNULL(p.[code],'') AS code
        ,ISNULL(p.[dateOfExpire],'') AS dateOfExpire
        ,p.[productFormId]
        ,p.[manufactureId]
        ,ISNULL(p.[description],'') AS description
        ,p.[productCategoryId] AS categoryId
        ,p.[companyId]
        ,p.[trackInventory]
        ,ISNULL(inv.stockQuantity, 0) AS stockQuantity
        ,p.[createdAt]
        ,ISNULL(p.[updatedAt],'') AS updatedAt
        
        -- 1. Nested Details Object (Returns as an array/object matching your save logic)
        ,(
            SELECT 
                ISNULL(inv.stockQuantity, 0) AS stockQuantity
                ,pd.unitPrice
                ,pd.salePrice
            FROM dbo.productDetails pd
            WHERE pd.productId = p.productId
            FOR JSON PATH
        ) AS productDetails

        -- 2. Nested Descriptions Array
        ,(
            SELECT 
                pdesc.Dosage
                ,pdesc.measurementId
                ,pdesc.is_principal
                ,pdesc.activeIngredientId
            FROM dbo.productsDescription pdesc
            WHERE pdesc.productId = p.productId
            FOR JSON PATH
        ) AS productDescriptions

        -- 3. Nested Options and nested Choices Array
        ,(
            SELECT 
                po.optionKey
                ,po.name
                ,po.type
                ,(
                    SELECT 
                        poc.choiceKey
                        ,poc.name
                        ,poc.price
                        ,poc.description
                    FROM dbo.productOptionChoices poc
                    WHERE poc.productOptionId = po.productOptionId
                    FOR JSON PATH
                ) AS optionChoices
            FROM dbo.productOptions po
            WHERE po.productId = p.productId
            FOR JSON PATH
        ) AS productOptions

    FROM 
        [dbo].[products] p
    LEFT JOIN dbo.inventoryStock inv
        ON inv.companyId = p.companyId AND inv.productId = p.productId
    WHERE
        p.productId = @productId
    FOR JSON PATH, ROOT('products');

END
GO

-- dbo.sp_products_save
CREATE OR ALTER PROC [dbo].[sp_products_save]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = '{"result":[{ "value":"", "msg":"", "error":"" }]}',
        @Error NVARCHAR(500) = '',
        @action INT,
        @companyId INT,
        @productId INT;

    BEGIN TRY
        -- 1. Extract Root Context
        SELECT TOP (1)
            @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
            @companyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
            @productId = TRY_CAST(JSON_VALUE(value, '$.productId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.products');

        -- Validations
        IF @action IS NULL RAISERROR('action is required (1=insert, 2=update, 3=delete).', 16, 1);
        IF @companyId IS NULL RAISERROR('companyId is required.', 16, 1);
        IF @companyId <> 1 RAISERROR('Invalid companyId.', 16, 1);

        BEGIN TRANSACTION;

        /* ============================================================
           STEP 1: BASE PRODUCTS
           ============================================================ */
        IF @action = 1
        BEGIN
            -- Code is an identity-like counter per company: MAX(numeric code) + 1,
            -- never typed by the user. UPDLOCK+HOLDLOCK keeps two concurrent
            -- inserts from reading the same MAX (we are inside the transaction).
            DECLARE @nextCode VARCHAR(100) = CAST(
                ISNULL((SELECT MAX(TRY_CAST(code AS BIGINT))
                        FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
                        WHERE companyId = @companyId), 0) + 1 AS VARCHAR(100));

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, productCategoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice, trackInventory)
            SELECT 
                JSON_VALUE(value, '$.name'), JSON_VALUE(value, '$.barCode'), @nextCode,
                TRY_CONVERT(DATE, NULLIF(JSON_VALUE(value, '$.dateOfExpire'), '')), TRY_CAST(JSON_VALUE(value, '$.productFormId') AS INT),
                TRY_CAST(JSON_VALUE(value, '$.manufactureId') AS INT), JSON_VALUE(value, '$.description'),
                GETDATE(), TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'), JSON_VALUE(value, '$.categoryId')) AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT), 0),
                TRY_CAST(JSON_VALUE(value, '$.netContent') AS DECIMAL(10,3)), NULLIF(JSON_VALUE(value, '$.unitOfMeasure'), ''),
                TRY_CAST(JSON_VALUE(value, '$.referencePrice') AS DECIMAL(10,2)),
                -- trackInventory: explicit value wins; otherwise physical goods (barcode / supply) are tracked.
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.trackInventory') AS BIT),
                         CASE WHEN NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.barCode'))), '') IS NOT NULL
                                OR TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT) = 1 THEN 1 ELSE 0 END)
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            IF @productId IS NULL RAISERROR('productId is required for update.', 16, 1);

            UPDATE p
            SET p.name = COALESCE(JSON_VALUE(j.value, '$.name'), p.name),
                p.barCode = COALESCE(JSON_VALUE(j.value, '$.barCode'), p.barCode),
                -- code is never changed after insert (auto-assigned identity)
                p.dateOfExpire = CASE
                    WHEN TRY_CAST(JSON_VALUE(j.value, '$.noExpire') AS BIT) = 1 THEN NULL
                    ELSE COALESCE(TRY_CONVERT(DATE, NULLIF(JSON_VALUE(j.value, '$.dateOfExpire'), '')), p.dateOfExpire)
                END,
                -- netContent/unitOfMeasure/referencePrice: the wizard always sends all three (null = cleared)
                p.netContent = TRY_CAST(JSON_VALUE(j.value, '$.netContent') AS DECIMAL(10,3)),
                p.unitOfMeasure = NULLIF(JSON_VALUE(j.value, '$.unitOfMeasure'), ''),
                p.referencePrice = TRY_CAST(JSON_VALUE(j.value, '$.referencePrice') AS DECIMAL(10,2)),
                p.productFormId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.productFormId') AS INT), p.productFormId),
                p.manufactureId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.manufactureId') AS INT), p.manufactureId),
                p.description = COALESCE(JSON_VALUE(j.value, '$.description'), p.description),
                p.updatedAt = GETDATE(),
                p.productCategoryId = COALESCE(TRY_CAST(COALESCE(JSON_VALUE(j.value, '$.productCategoryId'), JSON_VALUE(j.value, '$.categoryId')) AS INT), p.productCategoryId),
                p.isSupply = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isSupply') AS BIT), p.isSupply),
                p.trackInventory = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.trackInventory') AS BIT), p.trackInventory)
            FROM dbo.products p
            CROSS APPLY OPENJSON(@pjsonfile, '$.products') j
            WHERE p.productId = @productId AND p.companyId = @companyId;
        END
        ELSE IF @action = 3
        BEGIN
            -- Clean up everything associated with this product (Cascade Delete)
            DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
            DELETE FROM dbo.productOptions WHERE productId = @productId;
            DELETE FROM dbo.productDetails WHERE productId = @productId;
            DELETE FROM dbo.inventoryStock WHERE productId = @productId AND companyId = @companyId;
            IF OBJECT_ID('dbo.productsDescription', 'U') IS NOT NULL DELETE FROM dbo.productsDescription WHERE productId = @productId;
            DELETE FROM dbo.products WHERE productId = @productId AND companyId = @companyId;

            COMMIT TRANSACTION;
            
            -- Early return on successful delete
            SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@productId AS NVARCHAR(50))), '$.result[0].msg', 'Deleted Successfully');
            SELECT JSON_VALUE(value, '$.value') AS [value], JSON_VALUE(value, '$.msg') AS [msg], JSON_VALUE(value, '$.error') AS [error] FROM OPENJSON(@Outputmessage, '$.result');
            RETURN;
        END

        /* ============================================================
           STEP 2: PRODUCT DETAILS (Simple IF EXISTS Check)
           ============================================================ */
        DECLARE @stock INT, @uPrice DECIMAL(10,2), @sPrice DECIMAL(10,2);
        
        SELECT 
            @stock = TRY_CAST(JSON_VALUE(value, '$.stockQuantity') AS INT),
            @uPrice = TRY_CAST(JSON_VALUE(value, '$.unitPrice') AS DECIMAL(10,2)),
            @sPrice = TRY_CAST(JSON_VALUE(value, '$.salePrice') AS DECIMAL(10,2))
        FROM OPENJSON(@pjsonfile, '$.productDetails');

        -- productDetails keeps prices only. stockQuantity there is frozen since phase 1
        -- (2026-10-15c): the only stock is dbo.inventoryStock + dbo.inventoryMovements.
        IF EXISTS (SELECT 1 FROM dbo.productDetails WHERE productId = @productId)
        BEGIN
            UPDATE dbo.productDetails
            SET unitPrice = COALESCE(@uPrice, unitPrice),
                salePrice = COALESCE(@sPrice, salePrice),
                updatedAt = GETDATE()
            WHERE productId = @productId;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
            VALUES (@productId, 0, COALESCE(@uPrice, 0), COALESCE(@sPrice, 0), GETDATE(), GETDATE());
        END

        -- The stock typed in the wizard is a target count: post the difference as
        -- 'opening' (first count) or 'adjustment' (recount). A non-zero stock turns
        -- tracking on; a 0 on an untracked product (e.g. made-to-order food) is ignored.
        IF @stock IS NOT NULL
           AND (@stock <> 0 OR EXISTS (SELECT 1 FROM dbo.products
                                       WHERE productId = @productId AND trackInventory = 1))
        BEGIN
            DECLARE @current DECIMAL(18,3), @hasStockRow BIT = 0, @stockUserId INT,
                    @stockDelta DECIMAL(18,3), @stockReason VARCHAR(30);

            SELECT @current = stockQuantity, @hasStockRow = 1
            FROM dbo.inventoryStock WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND productId = @productId;

            SELECT TOP (1) @stockUserId = TRY_CAST(JSON_VALUE(value, '$.userId') AS INT)
            FROM OPENJSON(@pjsonfile, '$.products');

            UPDATE dbo.products SET trackInventory = 1
            WHERE productId = @productId AND trackInventory = 0;

            SET @stockDelta  = @stock - ISNULL(@current, 0);
            SET @stockReason = CASE WHEN @hasStockRow = 1 THEN 'adjustment' ELSE 'opening' END;

            IF @stockDelta <> 0
                EXEC dbo.sp_inventory_post
                    @companyId = @companyId,
                    @productId = @productId,
                    @quantityDelta = @stockDelta,
                    @reason = @stockReason,
                    @refType = 'product_save',
                    @refId = @productId,
                    @userId = @stockUserId,
                    @notes = N'Stock capturado en el asistente de producto';
        END

        /* ============================================================
           STEP 3: PRODUCT DESCRIPTIONS
           ============================================================ */
        IF OBJECT_ID('dbo.productsDescription', 'U') IS NOT NULL
        BEGIN
            DELETE FROM dbo.productsDescription WHERE productId = @productId;

            INSERT INTO dbo.productsDescription (productId, Dosage, measurementId, is_principal, activeIngredientId)
            SELECT 
                @productId, JSON_VALUE(value, '$.Dosage'), 
                TRY_CAST(JSON_VALUE(value, '$.measurementId') AS INT), 
                JSON_VALUE(value, '$.is_principal'), 
                TRY_CAST(JSON_VALUE(value, '$.activeIngredientId') AS INT)
            FROM OPENJSON(@pjsonfile, '$.productDescriptions');
        END

        /* ============================================================
           STEP 4: OPTIONS AND CHOICES (Simple Loop/Insert Pattern)
           ============================================================ */
        -- Clear old configurations to avoid messy updates
        DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
        DELETE FROM dbo.productOptions WHERE productId = @productId;

        -- We use a cursor or simple loop over the array index to keep identities synchronized
        DECLARE @index INT = 0, @maxOptions INT;
        SET @maxOptions = (SELECT COUNT(*) FROM OPENJSON(@pjsonfile, '$.productOptions'));

        WHILE @index < @maxOptions
        BEGIN
            DECLARE @optPath NVARCHAR(100) = '$.productOptions[' + CAST(@index AS NVARCHAR(10)) + ']';
            DECLARE @newOptId INT;

            -- Insert the Option Node
            INSERT INTO dbo.productOptions (productId, optionKey, name, type, createdAt, updatedAt)
            SELECT @productId, JSON_VALUE(@pjsonfile, @optPath + '.optionKey'), JSON_VALUE(@pjsonfile, @optPath + '.name'), JSON_VALUE(@pjsonfile, @optPath + '.type'), GETDATE(), GETDATE();
            
            SET @newOptId = SCOPE_IDENTITY();

            -- Insert Nested Choices matching this exact option index
            INSERT INTO dbo.productOptionChoices (productOptionId, choiceKey, name, price, description, createdAt, updatedAt)
            SELECT 
                @newOptId,
                JSON_VALUE(value, '$.choiceKey'),
                JSON_VALUE(value, '$.name'),
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.price') AS DECIMAL(10,2)), 0.00),
                COALESCE(JSON_VALUE(value, '$.description'), ''),
                GETDATE(),
                GETDATE()
            FROM OPENJSON(@pjsonfile, @optPath + '.optionChoices');

            SET @index = @index + 1;
        END

        COMMIT TRANSACTION;

        -- Success Output Compilation
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@productId AS NVARCHAR(50))), '$.result[0].msg', CASE WHEN @action = 1 THEN 'Inserted Successfully' ELSE 'Updated Successfully' END);

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, '$.result[0].error', '1'), '$.result[0].msg', @Error);
    END CATCH;

    -- Return Status Response
    SELECT JSON_VALUE(value, '$.value') AS [value], JSON_VALUE(value, '$.msg') AS [msg], JSON_VALUE(value, '$.error') AS [error] FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- 6) Verify ------------------------------------------------------------------------------
-- a) both triggers exist (expect 2 rows)
SELECT name AS triggerName, OBJECT_NAME(parent_id) AS tableName, is_disabled
FROM sys.triggers
WHERE name IN ('trg_incomeDetails_inventory', 'trg_expenseDetails_inventory');

-- b) tracked products: ledger stock vs the frozen productDetails number (equal right after the migration)
SELECT p.companyId, p.productId, p.name, p.trackInventory,
       s.stockQuantity AS inventoryStock,
       (SELECT TOP 1 d.stockQuantity FROM dbo.productDetails d
        WHERE d.productId = p.productId ORDER BY d.productDetailId) AS productDetailsStock_frozen
FROM dbo.products p
LEFT JOIN dbo.inventoryStock s ON s.companyId = p.companyId AND s.productId = p.productId
ORDER BY p.trackInventory DESC, p.companyId, p.name;

-- c) balance = sum of movements (expect 0 rows; rows that existed before this
--    migration without movements show up here and only need one 'adjustment')
SELECT s.companyId, s.productId, s.stockQuantity, ISNULL(m.total, 0) AS movementsTotal
FROM dbo.inventoryStock s
LEFT JOIN (SELECT companyId, productId, SUM(quantityDelta) AS total
           FROM dbo.inventoryMovements GROUP BY companyId, productId) m
       ON m.companyId = s.companyId AND m.productId = s.productId
WHERE s.stockQuantity <> ISNULL(m.total, 0);
GO

-- Re-enable execution (a failed pre-check above turns NOEXEC on for the rest of the file).
SET NOEXEC OFF;
GO
