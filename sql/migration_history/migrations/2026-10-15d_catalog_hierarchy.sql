-- =============================================================================
-- Catalog hierarchy: Categoría → Subcategoría → Producto (+ required options, inactive products)
-- =============================================================================
-- NOT YET EXECUTED. Run manually against the live DB AFTER
-- 2026-10-15c_inventory_single_source.sql (redeploys the product SPs from it).
--
-- WHY (GMO Lavandería catalog): products need a 3-level catalog — Servicios › Lavado
--   › Servicio de lavado — and options such as "Ciclo" must be mandatory, otherwise
--   a wash can be sold at the $0 base price. Old pseudo-products ("Bebidas",
--   "Productos Limpieza", whose options were the real items) must disappear from
--   the POS without deleting them (past sales point to them).
--
-- WHAT:
--   1. productCategories.parentCategoryId (NULL = top-level). Two levels only: the
--      parent must be a top-level category of the same company. FK to itself.
--      products.productCategoryId keeps pointing to ONE category (normally the
--      subcategory), so existing products and categories keep working as top-level.
--   2. productOptions.isRequired BIT (default 0). Price model unchanged:
--      line = base salePrice + Σ chosen choices ("base $0 + Básico $40 = $40").
--   3. products.isActive BIT (default 1). Inactive products are hidden from the POS.
--   4. SPs:
--      sp_products_categories      insert/update parentCategoryId (validated); insert
--                                  returns the new id in result[0].value.
--      sp_products_categories_all  returns parentCategoryId (top-level first).
--      sp_products_by_company      hides isActive = 0 (unless "includeInactive": 1);
--                                  categoryId of a top-level category also returns its
--                                  subcategories' products; returns isActive,
--                                  category.parentCategoryId, options[].isRequired.
--      sp_products_one             returns isActive and productOptions[].isRequired.
--      sp_products_save            accepts isActive and productOptions[].isRequired.
--   NOTE: sp_products_save re-creates options on every save — a client that does
--   not send isRequired yet resets it to 0. Ship the frontend toggle with this.
-- ROLLBACK: 2026-10-15d_catalog_hierarchy_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.products', 'trackInventory') IS NULL
    BEGIN RAISERROR('products.trackInventory missing — run 2026-10-15c_inventory_single_source.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
GO

-- 1) productCategories.parentCategoryId ------------------------------------------------
IF COL_LENGTH('dbo.productCategories', 'parentCategoryId') IS NULL
    ALTER TABLE dbo.productCategories ADD parentCategoryId INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_productCategories_parent')
    EXEC (N'ALTER TABLE dbo.productCategories WITH CHECK
            ADD CONSTRAINT FK_productCategories_parent
            FOREIGN KEY (parentCategoryId) REFERENCES dbo.productCategories (productCategoryId);');
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_productCategories_parent'
               AND object_id = OBJECT_ID('dbo.productCategories'))
    EXEC (N'CREATE NONCLUSTERED INDEX IX_productCategories_parent ON dbo.productCategories (companyId, parentCategoryId);');
RAISERROR('OK: productCategories.parentCategoryId', 0, 1) WITH NOWAIT;
GO

-- 2) productOptions.isRequired ---------------------------------------------------------
IF COL_LENGTH('dbo.productOptions', 'isRequired') IS NULL
    ALTER TABLE dbo.productOptions ADD isRequired BIT NOT NULL
        CONSTRAINT DF_productOptions_isRequired DEFAULT (0);
RAISERROR('OK: productOptions.isRequired', 0, 1) WITH NOWAIT;
GO

-- 3) products.isActive -----------------------------------------------------------------
IF COL_LENGTH('dbo.products', 'isActive') IS NULL
    ALTER TABLE dbo.products ADD isActive BIT NOT NULL
        CONSTRAINT DF_products_isActive DEFAULT (1);
RAISERROR('OK: products.isActive', 0, 1) WITH NOWAIT;
GO

-- 4) Stored procedures -----------------------------------------------------------------

-- dbo.sp_products_categories
CREATE OR ALTER PROC [dbo].[sp_products_categories]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    -- EXAMPLES --

    

    -- 1) INSERT (one or many)
    DECLARE @pjsonfile NVARCHAR(MAX) = '{
      "productCategories": [
        { "action": 1, "name": "Detergentes", "image": "detergentes.png", "companyId": 3 },
        { "action": 1, "name": "Suavizantes", "image": "suavizantes.png", "companyId": 3 }
      ]
    }';

    */

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = '{
          "result":[{ "value":"", "msg":"", "error":"" }]
        }',
        @Error NVARCHAR(500) = '',
        @action INT,
        @filterCompanyId INT = NULL,
        @filterCategoryId INT = NULL;

    -- Read action and optional filters from the first element
    SELECT TOP (1)
        @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
        @filterCompanyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        @filterCategoryId = TRY_CAST(JSON_VALUE(value, '$.categoryId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.productCategories');

    BEGIN TRY

        BEGIN TRANSACTION;

        -- Subcategories: parentCategoryId must be a TOP-LEVEL category of the same
        -- company (two levels: Categoría → Subcategoría). 0 on update = make it top-level.
        IF EXISTS (
            SELECT 1
            FROM OPENJSON(@pjsonfile, '$.productCategories') j
            CROSS APPLY (SELECT NULLIF(TRY_CAST(JSON_VALUE(j.value, '$.parentCategoryId') AS INT), 0) AS parentId,
                                TRY_CAST(JSON_VALUE(j.value, '$.productCategoryId') AS INT) AS selfId,
                                TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT) AS companyId) x
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) IN (1, 2)
              AND x.parentId IS NOT NULL
              AND (x.parentId = x.selfId
                   OR NOT EXISTS (SELECT 1 FROM dbo.productCategories pc
                                  WHERE pc.productCategoryId = x.parentId
                                    AND pc.parentCategoryId IS NULL
                                    AND (x.companyId IS NULL OR pc.companyId = x.companyId))
                   OR EXISTS (SELECT 1 FROM dbo.productCategories ch WHERE ch.parentCategoryId = x.selfId))
        )
            THROW 50201, 'parentCategoryId inválido: debe ser una categoría principal de la misma empresa (y una categoría con subcategorías no puede ser subcategoría).', 1;

        IF @action = 1
        BEGIN
            -- INSERT (supports multiple rows)
            DECLARE @Inserted TABLE (productCategoryId INT);

            INSERT INTO [dbo].[productCategories] ([name], [image], [companyId], [parentCategoryId])
            OUTPUT inserted.productCategoryId INTO @Inserted(productCategoryId)
            SELECT
                JSON_VALUE(j.value, '$.name'),
                JSON_VALUE(j.value, '$.image'),
                TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT),
                NULLIF(TRY_CAST(JSON_VALUE(j.value, '$.parentCategoryId') AS INT), 0)
            FROM OPENJSON(@pjsonfile, '$.productCategories') AS j
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) = 1;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST((SELECT MAX(productCategoryId) FROM @Inserted) AS NVARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', CONCAT('Inserted Successfully (', (SELECT COUNT(*) FROM @Inserted), ' row(s))'));
        END
        ELSE IF @action = 2
        BEGIN
            -- UPDATE (supports multiple rows)
            UPDATE pc
            SET
                pc.[name]  = COALESCE(JSON_VALUE(j.value, '$.name'), pc.[name]),
                pc.[image] = COALESCE(JSON_VALUE(j.value, '$.image'), pc.[image]),
                pc.[companyId] = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT), pc.[companyId]),
                -- missing/null = keep, 0 = top-level, n = subcategory of n
                pc.[parentCategoryId] = CASE
                    WHEN TRY_CAST(JSON_VALUE(j.value, '$.parentCategoryId') AS INT) IS NULL THEN pc.[parentCategoryId]
                    ELSE NULLIF(TRY_CAST(JSON_VALUE(j.value, '$.parentCategoryId') AS INT), 0)
                END
            FROM [dbo].[productCategories] pc
            INNER JOIN OPENJSON(@pjsonfile, '$.productCategories') j
                ON pc.productCategoryId = TRY_CAST(JSON_VALUE(j.value, '$.productCategoryId') AS INT)
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) = 2;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- DELETE (supports multiple ids)
            DELETE pc
            FROM [dbo].[productCategories] pc
            INNER JOIN OPENJSON(@pjsonfile, '$.productCategories') j
                ON pc.productCategoryId = TRY_CAST(JSON_VALUE(j.value, '$.productCategoryId') AS INT)
            WHERE TRY_CAST(JSON_VALUE(j.value, '$.action') AS INT) = 3;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            -- Unknown action
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid or missing action (use 0=list, 1=insert, 2=update, 3=delete)');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Unified status response for non-list actions
    -- Unified status response for non-list actions
SELECT 
    (
        SELECT
            JSON_VALUE(value, '$.value') AS [value],
            JSON_VALUE(value, '$.msg')   AS [msg],
            JSON_VALUE(value, '$.error') AS [error]
        FROM OPENJSON(@Outputmessage, '$.result')
        FOR JSON PATH, ROOT('result')
    ) AS json_output;

END
GO

-- dbo.sp_products_categories_all
CREATE OR ALTER PROC [dbo].[sp_products_categories_all]
    @pjsonfile NVARCHAR(MAX)
AS

BEGIN
    SET NOCOUNT ON;

   /*
    DECLARE @pjsonfile NVARCHAR(MAX) = '{
      "productCategories": [
        { "companyId": 1, "categoryId": null }
      ]
    }';
    */

    DECLARE 
        @Outputmessage NVARCHAR(MAX) = '{
          "result":[{ "value":"", "msg":"", "error":"" }]
        }',
        @Error NVARCHAR(500) = '',
        @action INT,
        @filterCompanyId INT = NULL,
        @filterCategoryId INT = NULL;

    -- Read action and optional filters from the first element
    SELECT TOP (1)
        @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
        @filterCompanyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        @filterCategoryId = TRY_CAST(JSON_VALUE(value, '$.categoryId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.productCategories');

    
    -- LIST
    SELECT
        [productCategoryId] AS [categoryId],
        [name],
        [image],
        [companyId],
        [parentCategoryId]          -- NULL = top-level category; otherwise a subcategory of it
    FROM [dbo].[productCategories]
    WHERE (@filterCompanyId IS NULL OR companyId = @filterCompanyId)
        AND (@filterCategoryId IS NULL OR productCategoryId = @filterCategoryId)
    ORDER BY CASE WHEN [parentCategoryId] IS NULL THEN 0 ELSE 1 END, [name]
    FOR JSON PATH, ROOT('productCategories');

END
GO

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

-- 5) Verify ------------------------------------------------------------------------------
SELECT
    CASE WHEN COL_LENGTH('dbo.productCategories', 'parentCategoryId') IS NOT NULL THEN 1 ELSE 0 END AS parentCategoryId,
    CASE WHEN COL_LENGTH('dbo.productOptions', 'isRequired')          IS NOT NULL THEN 1 ELSE 0 END AS isRequired,
    CASE WHEN COL_LENGTH('dbo.products', 'isActive')                  IS NOT NULL THEN 1 ELSE 0 END AS isActive;

EXEC dbo.sp_products_categories_all '{ "productCategories": [ { "companyId": 1 } ] }';
GO

-- Re-enable execution (a failed pre-check above turns NOEXEC on for the rest of the file).
SET NOEXEC OFF;
GO
