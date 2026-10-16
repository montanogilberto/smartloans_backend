-- ROLLBACK for 2026-10-15_products_productCategoryId.sql
-- Drops FK + index, renames productCategoryId back to categoryId and restores
-- the SP definitions that were deployed right before the migration.

SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_products_productCategories')
    ALTER TABLE dbo.products DROP CONSTRAINT FK_products_productCategories;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_products_productCategoryId'
           AND object_id = OBJECT_ID('dbo.products'))
    DROP INDEX IX_products_productCategoryId ON dbo.products;

IF COL_LENGTH('dbo.products', 'productCategoryId') IS NOT NULL
   AND COL_LENGTH('dbo.products', 'categoryId') IS NULL
    EXEC sp_rename 'dbo.products.productCategoryId', 'categoryId', 'COLUMN';

COMMIT TRANSACTION;
GO

-- dbo.one_products sp_inventory_list sp_orders_all sp_orders_one sp_products sp_products_by_company sp_products_food sp_products_one sp_products_save
GO

-- dbo.one_products
CREATE OR ALTER PROC dbo.one_products
    @productId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.productId,
        p.name,
        ISNULL(p.barCode, '') AS barCode,
        ISNULL(p.code, '') AS code,
        CONVERT(varchar(10), p.dateOfExpire, 23) AS dateOfExpire, -- yyyy-mm-dd
        ISNULL(p.productFormId, 0) AS productFormId,
        ISNULL(p.manufactureId, 0) AS manufactureId,
        ISNULL(p.description, '') AS description,
        p.categoryId,
        p.companyId,
        p.createdAt,
        p.updatedAt,

        -- productDetails (array)
        JSON_QUERY(
            ISNULL((
                SELECT
                    pd.stockQuantity,
                    pd.unitPrice,
                    pd.salePrice
                FROM dbo.product_details pd
                WHERE pd.productId = p.productId
                FOR JSON PATH
            ), '[]')
        ) AS productDetails,

        -- productOptions (array), each with optionChoices (array)
        JSON_QUERY(
            ISNULL((
                SELECT
                    po.optionKey,
                    po.name,
                    po.[type],

                    JSON_QUERY(
                        ISNULL((
                            SELECT
                                poc.choiceKey,
                                poc.name,
                                poc.price,
                                ISNULL(poc.description, '') AS description
                            FROM dbo.product_option_choices poc
                            WHERE poc.productOptionId = po.productOptionId
                            ORDER BY poc.productOptionChoiceId
                            FOR JSON PATH
                        ), '[]')
                    ) AS optionChoices

                FROM dbo.product_options po
                WHERE po.productId = p.productId
                ORDER BY po.productOptionId
                FOR JSON PATH
            ), '[]')
        ) AS productOptions

    FROM dbo.products p
    WHERE p.productId = @productId
    FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_inventory_list
CREATE OR ALTER PROC dbo.sp_inventory_list
(
    @companyId INT
)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.productId,
        p.name AS productName,

        ISNULL(s.stockQuantity, 0) AS stockQuantity,
        ISNULL(s.minStockQty, 0)   AS minStockQty,

        pd.unitPrice,
        pd.salePrice,

        p.barCode,
        p.code,
        p.categoryId
    FROM dbo.products p
    LEFT JOIN dbo.productDetails pd
        ON pd.productId = p.productId
    LEFT JOIN dbo.inventoryStock s
        ON s.companyId = @companyId
       AND s.productId = p.productId
    WHERE p.companyId = @companyId
    ORDER BY p.name
    FOR JSON PATH, ROOT('result');
END
GO

-- dbo.sp_orders_all
CREATE OR ALTER PROC [dbo].[sp_orders_all]
AS
BEGIN
    SET NOCOUNT ON;

        SELECT
        o_main.orderId,
        o_main.clientId,
        o_main.total,
        o_main.paymentMethod,
        o_main.comments,
        o_main.createdAt,
        (
            SELECT 
                p.productId AS [id],
                p.name,
                p.description,
                --pd.saleprice AS price,
                NULL AS [image],
                p.categoryId,
                (
                    SELECT 
                        po.productOptionId AS [id],
                        po.name,
                        po.type,
                        (
                            SELECT 
                                poc.choiceKey AS [id],
                                poc.name,
                                poc.price
                            FROM productOptionChoices poc
                            WHERE poc.productOptionId = po.productOptionId
                            FOR JSON PATH
                        ) AS choices
                    FROM productOptions po
                    WHERE po.productId = p.productId
                    FOR JSON PATH
                ) AS options
            FROM orders o
            INNER JOIN products p ON o.productId = p.productId
            LEFT JOIN productsDescription pd ON pd.productId = p.productId
            WHERE o.orderId = o_main.orderId
            GROUP BY p.productId, p.name, p.description,  p.categoryId
            FOR JSON PATH
        ) AS products_food
    FROM orders o_main
    GROUP BY o_main.orderId, o_main.clientId, o_main.total, o_main.paymentMethod, o_main.comments, o_main.createdAt
    FOR JSON PATH;


END
GO

-- dbo.sp_orders_one
CREATE OR ALTER PROC [dbo].[sp_orders_one] (@pjsonfile NVARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    /* 
    DECLARE @pjsonfile NVARCHAR(MAX) = N'{
      "orders": [
        {
          "orderId": 1
        }
      ]
    }'
   */

    DECLARE @OutputMessage NVARCHAR(MAX) = '{
    "result": [
        { "value": "", "msg": "", "error": "" }
    ]
    }',
    @orderId INT;

    -- Extract orderId from JSON input
    SET @orderId = CAST((
        SELECT JSON_VALUE(value, '$.orderId') 
        FROM OPENJSON(@pjsonfile, '$.orders')
    ) AS INT);

    SELECT
        o_main.orderId,
        o_main.clientId,
        o_main.total,
        o_main.paymentMethod,
        o_main.comments,
        o_main.createdAt,
        (
            SELECT 
                p.productId AS [id],
                p.name,
                p.description,
                --pd.saleprice AS price,
                NULL AS [image],
                p.categoryId,
                (
                    SELECT 
                        po.productOptionId AS [id],
                        po.name,
                        po.type,
                        (
                            SELECT 
                                poc.choiceKey AS [id],
                                poc.name,
                                poc.price
                            FROM productOptionChoices poc
                            WHERE poc.productOptionId = po.productOptionId
                            FOR JSON PATH
                        ) AS choices
                    FROM productOptions po
                    WHERE po.productId = p.productId
                    FOR JSON PATH
                ) AS options
            FROM orders o
            INNER JOIN products p ON o.productId = p.productId
            LEFT JOIN productsDescription pd ON pd.productId = p.productId
            WHERE o.orderId = o_main.orderId
            GROUP BY p.productId, p.name, p.description,  p.categoryId
            FOR JSON PATH
        ) AS products_food
    FROM orders o_main
    WHERE o_main.orderId = @orderId
    GROUP BY o_main.orderId, o_main.clientId, o_main.total, o_main.paymentMethod, o_main.comments, o_main.createdAt
    FOR JSON PATH;



END
GO

-- dbo.sp_products
CREATE OR ALTER PROC [dbo].[sp_products] (@pjsonfile VARCHAR(MAX))
-- INSERT --> 1
-- UPDATE --> 2
-- DELETE --> 3
AS
SET NOCOUNT ON;

/*
DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
            "productId": 1,
            "name": "exaliv",
            "barCode": "",
            "code": "",
            "dateOfExpire": "2024-03-12",
            "productFormId": 1,
            "manufactureId": 1,
            "description": "",
            "createdAt": "2024-03-12T20:31:06.490",
            "updatedAt": "1900-01-01T00:00:00",
            "companyId": 1,
            "action": 1
            
        }
    ]
}'
*/

DECLARE @Outputmessage NVARCHAR(MAX) = '
{
  "result": [
  {
     "value": "",
     "msg": "",
     "error": ""
   }
  ]
}',
@Error NVARCHAR(500) = '',
@action INT,
@product_id INT,
@companyId INT;

BEGIN
    -- Read action and companyId from the JSON payload
    SET @action = (
        SELECT TOP 1 JSON_VALUE(value, '$.action')
        FROM OPENJSON(@pjsonfile, '$.products')
    );

    SET @companyId = (
        SELECT TOP 1 TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.products')
    );

    BEGIN TRY
        -- Validate companyId is present and equals 1
        IF @companyId IS NULL
        BEGIN
            RAISERROR('companyId is required.', 16, 1);
        END;

        IF @companyId <> 1
        BEGIN
            RAISERROR('Invalid companyId. ', 16, 1);
        END;

        -- Validate company exists
        IF NOT EXISTS (SELECT 1 FROM [dbo].[companies] WHERE [companyId] = @companyId)
        BEGIN
            RAISERROR('The specified companyId does not exist.', 16, 1);
        END;

        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- INSERT (scoped to companyId)
            INSERT INTO [dbo].[products] (
                [name],
                [barCode],
                [code],
                [dateOfExpire],
                [productFormId],
                [manufactureId],
                [description],
                [createdAt],
                [updatedAt],
                [categoryId],
                [companyId]
            )
            SELECT
                JSON_VALUE(value, '$.name'),
                JSON_VALUE(value, '$.barCode'),
                JSON_VALUE(value, '$.code'),
                JSON_VALUE(value, '$.dateOfExpire'),
                JSON_VALUE(value, '$.productFormId'),
                JSON_VALUE(value, '$.manufactureId'),
                JSON_VALUE(value, '$.description'),
                GETDATE(),
                NULL,
                JSON_VALUE(value, '$.categoryId'),
                @companyId
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @product_id = SCOPE_IDENTITY();
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@product_id AS NVARCHAR(50)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- UPDATE (only update rows that belong to companyId)
            UPDATE p
            SET 
                p.[name]          = JSON_VALUE(j.value, '$.name'),
                p.[barCode]       = JSON_VALUE(j.value, '$.barCode'),
                p.[code]          = JSON_VALUE(j.value, '$.code'),
                p.[dateOfExpire]  = JSON_VALUE(j.value, '$.dateOfExpire'),
                p.[productFormId] = JSON_VALUE(j.value, '$.productFormId'),
                p.[manufactureId] = JSON_VALUE(j.value, '$.manufactureId'),
                p.[description]   = JSON_VALUE(j.value, '$.description'),
                p.[createdAt]     = COALESCE(JSON_VALUE(j.value, '$.createdAt'), p.[createdAt]),
                p.[updatedAt]     = COALESCE(JSON_VALUE(j.value, '$.updatedAt'), GETDATE()),
                p.[categoryId]    = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.categoryId') AS INT), p.[categoryId]),
                p.[companyId]     = @companyId -- keep product scoped to this company
            FROM [dbo].[products] p
            INNER JOIN OPENJSON(@pjsonfile, '$.products') j
                ON p.[productId] = TRY_CAST(JSON_VALUE(j.value, '$.productId') AS INT)
               AND p.[companyId] = @companyId;  -- scope by company

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- DELETE (only delete rows that belong to companyId)
            DELETE p
            FROM [dbo].[products] p
            INNER JOIN OPENJSON(@pjsonfile, '$.products') j
                ON p.[productId] = TRY_CAST(JSON_VALUE(j.value, '$.productId') AS INT)
               AND p.[companyId] = @companyId; -- scope by company

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            RAISERROR('Invalid action. Use 1=INSERT, 2=UPDATE, 3=DELETE.', 16, 1);
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg')   AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

-- dbo.sp_products_by_company
CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'
    */

    DECLARE @companyId INT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.categoryId,
        ISNULL(p.code, '') AS code,
        ISNULL(p.barCode, '') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        (
            SELECT d.productDetailId, d.stockQuantity, d.unitPrice, d.salePrice
            FROM productDetails d
            WHERE d.productId = p.productId
            FOR JSON PATH
        ) AS details,
        JSON_QUERY((
            SELECT TOP 1 c.productCategoryId, c.name
            FROM productCategories c
            WHERE c.productCategoryId = p.categoryId
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
    OUTER APPLY (
        SELECT TOP 1 x.salePrice
        FROM productDetails x
        WHERE x.productId = p.productId
        ORDER BY x.productDetailId
    ) pd
    WHERE p.companyId = @companyId
      AND ISNULL(p.isSupply, 0) = 0
    ORDER BY p.name
    FOR JSON PATH, ROOT('products');
END
GO

-- dbo.sp_products_food
CREATE OR ALTER PROC [dbo].[sp_products_food]
  @pjsonfile NVARCHAR(MAX) = NULL
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @companyId INT = NULL;
  DECLARE @categoryId INT = NULL;

    /*
    @pjsonfile NVARCHAR(MAX) =  '{
    "products": [
        {
        "companyId": "1",
        "categoryId": "3"
        }
    ]
    }'
    */


  -- Extract companyId and categoryId from JSON
  IF @pjsonfile IS NOT NULL
  BEGIN
    SELECT TOP (1)
      @companyId = TRY_CAST(JSON_VALUE(j.value, '$.companyId') AS INT),
      @categoryId = TRY_CAST(JSON_VALUE(j.value, '$.categoryId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.products') AS j;
  END

  SELECT
      p.productId AS [id],
      p.name,
      p.description,
      pd.saleprice AS price,
      NULL AS [image],
      p.categoryId,
      (
        SELECT
            o.productOptionId AS [id],
            o.name,
            o.type,
            (
              SELECT
                  c.productOptionChoiceId AS [id],
                  c.name,
                  c.price
              FROM dbo.productOptionChoices AS c
              WHERE c.productOptionId = o.productOptionId
              FOR JSON PATH
            ) AS choices
        FROM dbo.productOptions AS o
        WHERE o.productId = p.productId
        FOR JSON PATH
      ) AS options
  FROM dbo.products AS p
  INNER JOIN dbo.productdetails AS pd
          ON pd.productId = p.productId
  WHERE EXISTS (SELECT 1 FROM dbo.productOptions o WHERE o.productId = p.productId)
    --AND (@companyId IS NULL OR p.companyId = @companyId)
    AND (@categoryId IS NULL OR p.categoryId = @categoryId)
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
        ,p.[categoryId]
        ,p.[companyId]
        ,p.[createdAt]
        ,ISNULL(p.[updatedAt],'') AS updatedAt
        
        -- 1. Nested Details Object (Returns as an array/object matching your save logic)
        ,(
            SELECT 
                pd.stockQuantity
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

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, categoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice)
            SELECT 
                JSON_VALUE(value, '$.name'), JSON_VALUE(value, '$.barCode'), @nextCode,
                TRY_CONVERT(DATE, NULLIF(JSON_VALUE(value, '$.dateOfExpire'), '')), TRY_CAST(JSON_VALUE(value, '$.productFormId') AS INT),
                TRY_CAST(JSON_VALUE(value, '$.manufactureId') AS INT), JSON_VALUE(value, '$.description'),
                GETDATE(), TRY_CAST(JSON_VALUE(value, '$.categoryId') AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT), 0),
                TRY_CAST(JSON_VALUE(value, '$.netContent') AS DECIMAL(10,3)), NULLIF(JSON_VALUE(value, '$.unitOfMeasure'), ''),
                TRY_CAST(JSON_VALUE(value, '$.referencePrice') AS DECIMAL(10,2))
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
                p.categoryId = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.categoryId') AS INT), p.categoryId),
                p.isSupply = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isSupply') AS BIT), p.isSupply)
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

        IF EXISTS (SELECT 1 FROM dbo.productDetails WHERE productId = @productId)
        BEGIN
            UPDATE dbo.productDetails
            SET stockQuantity = COALESCE(@stock, stockQuantity),
                unitPrice = COALESCE(@uPrice, unitPrice),
                salePrice = COALESCE(@sPrice, salePrice),
                updatedAt = GETDATE()
            WHERE productId = @productId;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
            VALUES (@productId, COALESCE(@stock, 0), COALESCE(@uPrice, 0), COALESCE(@sPrice, 0), GETDATE(), GETDATE());
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
