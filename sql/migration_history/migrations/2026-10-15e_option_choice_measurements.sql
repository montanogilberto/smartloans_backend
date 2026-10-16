-- =============================================================================
-- Option choices carry their own quantity + unit (19 L, 600 ml, 100 ml)
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-15d_catalog_hierarchy.sql (redeploys the product SPs from it).
--
-- WHY: a single option offers choices of different sizes — Garrafón › Tamaño:
--   19 L / 10 L / 3 L; Té Arizona › Sabor: Negro 600 ml / Mango 450 ml. The size
--   belongs to the CHOICE, not to the product, and the unit must be a reusable
--   catalog value instead of free text repeated in every name.
--
-- WHAT:
--   1. dbo.measurements gets the units the POS wizard already uses (prefix = code):
--      g, kg, ml, L, pz (mg already exists). Unique index on prefix.
--   2. productOptionChoices.quantity DECIMAL(10,3) NULL + measurementId INT NULL
--      (FK → measurements). Both optional: services ("Básico", "40 Min") have none.
--   3. SPs:
--      sp_products_save        choices accept "quantity" and "measurementId" or the
--                              unit code "unit" ("ml", "L"…, resolved by prefix).
--      sp_products_by_company  options[].choices[] return quantity, measurementId, unit.
--      sp_products_one         productOptions[].optionChoices[] return the same.
--   Prices unchanged: line = productDetails.salePrice + Σ chosen choice prices.
--   NOT changed on purpose: products.netContent / unitOfMeasure (the size of the
--   base product itself, used by the wizard's price-per-unit hint) and
--   products.productFormId → productForms (legacy pharmacy packing).
--   A choice is a variant WITHOUT its own stock or barcode: if a size must be
--   counted in inventory or scanned, make it its own product.
-- ROLLBACK: 2026-10-15e_option_choice_measurements_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.productOptions', 'isRequired') IS NULL
    BEGIN RAISERROR('productOptions.isRequired missing — run 2026-10-15d_catalog_hierarchy.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
GO

-- 1) Units --------------------------------------------------------------------------------
INSERT INTO dbo.measurements (name, prefix)
SELECT u.name, u.prefix
FROM (VALUES ('grams', 'g'), ('kilograms', 'kg'), ('milliliters', 'ml'),
             ('liters', 'L'), ('pieces', 'pz'), ('milligrams', 'mg')) AS u(name, prefix)
WHERE NOT EXISTS (SELECT 1 FROM dbo.measurements m WHERE m.prefix = u.prefix);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_measurements_prefix'
               AND object_id = OBJECT_ID('dbo.measurements'))
   AND NOT EXISTS (SELECT prefix FROM dbo.measurements GROUP BY prefix HAVING COUNT(*) > 1)
    CREATE UNIQUE NONCLUSTERED INDEX UQ_measurements_prefix ON dbo.measurements (prefix);

SELECT measurementId, name, prefix FROM dbo.measurements ORDER BY measurementId;
GO

-- 2) productOptionChoices.quantity + measurementId ----------------------------------------
IF COL_LENGTH('dbo.productOptionChoices', 'quantity') IS NULL
    ALTER TABLE dbo.productOptionChoices ADD quantity DECIMAL(10,3) NULL;
IF COL_LENGTH('dbo.productOptionChoices', 'measurementId') IS NULL
    ALTER TABLE dbo.productOptionChoices ADD measurementId INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_productOptionChoices_measurements')
    EXEC (N'ALTER TABLE dbo.productOptionChoices WITH CHECK
            ADD CONSTRAINT FK_productOptionChoices_measurements
            FOREIGN KEY (measurementId) REFERENCES dbo.measurements (measurementId);');
RAISERROR('OK: productOptionChoices.quantity / measurementId', 0, 1) WITH NOWAIT;
GO

-- 3) Stored procedures ---------------------------------------------------------------------

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
    DECLARE @includeInactive BIT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    -- Optional: productCategoryId (or legacy "categoryId"); missing/0 = all categories.
    SELECT TOP (1)
        @categoryId = NULLIF(TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'),
                                               JSON_VALUE(value, '$.categoryId')) AS INT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    -- Admin screens send includeInactive = 1 to see (and reactivate) hidden products; the POS never does.
    SELECT TOP (1) @includeInactive = ISNULL(TRY_CAST(JSON_VALUE(value, '$.includeInactive') AS BIT), 0)
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
        p.isActive,
        -- Stock lives only in inventoryStock (phase 1); details[] keeps its shape.
        ISNULL(inv.stockQuantity, 0) AS stockQuantity,
        (
            SELECT d.productDetailId, ISNULL(inv.stockQuantity, 0) AS stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name, c.parentCategoryId
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
                o.isRequired,
                (
                    SELECT
                        c.productOptionChoiceId AS [productOptionChoiceId],
                        c.name,
                        c.price,
                        c.quantity,                -- e.g. 19
                        c.measurementId,
                        m.prefix AS unit           -- e.g. 'L'
                    FROM productOptionChoices c
                    LEFT JOIN dbo.measurements m ON m.measurementId = c.measurementId
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
      AND (p.isActive = 1 OR @includeInactive = 1)
      -- A category also matches the products of its subcategories.
      AND (@categoryId IS NULL
           OR p.productCategoryId = @categoryId
           OR p.productCategoryId IN (SELECT sc.productCategoryId FROM dbo.productCategories sc
                                      WHERE sc.parentCategoryId = @categoryId))
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
        ,p.[isActive]
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
                ,po.isRequired
                ,(
                    SELECT 
                        poc.choiceKey
                        ,poc.name
                        ,poc.price
                        ,poc.description
                        ,poc.quantity
                        ,poc.measurementId
                        ,m.prefix AS unit
                    FROM dbo.productOptionChoices poc
                    LEFT JOIN dbo.measurements m ON m.measurementId = poc.measurementId
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

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, productCategoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice, trackInventory, isActive)
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
                                OR TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT) = 1 THEN 1 ELSE 0 END),
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isActive') AS BIT), 1)
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
                p.trackInventory = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.trackInventory') AS BIT), p.trackInventory),
                p.isActive = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isActive') AS BIT), p.isActive)
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
            INSERT INTO dbo.productOptions (productId, optionKey, name, type, isRequired, createdAt, updatedAt)
            SELECT @productId, JSON_VALUE(@pjsonfile, @optPath + '.optionKey'), JSON_VALUE(@pjsonfile, @optPath + '.name'), JSON_VALUE(@pjsonfile, @optPath + '.type'),
                   ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, @optPath + '.isRequired') AS BIT), 0), GETDATE(), GETDATE();
            
            SET @newOptId = SCOPE_IDENTITY();

            -- Insert Nested Choices matching this exact option index
            -- quantity + unit per choice (19 L, 600 ml): measurementId, or the unit code
            -- ("ml", "L", "kg"…) resolved against dbo.measurements.prefix.
            INSERT INTO dbo.productOptionChoices (productOptionId, choiceKey, name, price, description, quantity, measurementId, createdAt, updatedAt)
            SELECT 
                @newOptId,
                JSON_VALUE(value, '$.choiceKey'),
                JSON_VALUE(value, '$.name'),
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.price') AS DECIMAL(10,2)), 0.00),
                COALESCE(JSON_VALUE(value, '$.description'), ''),
                TRY_CAST(JSON_VALUE(value, '$.quantity') AS DECIMAL(10,3)),
                COALESCE(TRY_CAST(JSON_VALUE(value, '$.measurementId') AS INT),
                         (SELECT TOP (1) m.measurementId FROM dbo.measurements m
                          WHERE m.prefix = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.unit'))), ''))),
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

-- 4) Verify --------------------------------------------------------------------------------
SELECT
    CASE WHEN COL_LENGTH('dbo.productOptionChoices', 'quantity')      IS NOT NULL THEN 1 ELSE 0 END AS choiceQuantity,
    CASE WHEN COL_LENGTH('dbo.productOptionChoices', 'measurementId') IS NOT NULL THEN 1 ELSE 0 END AS choiceMeasurementId,
    (SELECT COUNT(*) FROM dbo.measurements) AS units;
GO

-- Re-enable execution (a failed pre-check above turns NOEXEC on for the rest of the file).
SET NOEXEC OFF;
GO
