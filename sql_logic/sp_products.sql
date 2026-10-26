-- dbo.sp_products — product insert/update/delete.
-- Source of truth only. To deploy, run the migration
-- sql/migration_history/migrations/2026-10-26_products_unify_sp_products.sql
-- (it also turns the deprecated write SP into an alias of this one).
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_products]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    Example (action: 1 = insert, 2 = update, 3 = delete). Every key except action and
    companyId is optional; on update a missing key keeps the current value (except
    netContent / unitOfMeasure / referencePrice: null clears them).
      products[0].productId          required for 2 and 3; ignored on insert
      products[0].code               not read: auto-assigned MAX(code) + 1 per company
      products[0].noExpire           update only: 1 clears dateOfExpire
      products[0].productCategoryId  alias: categoryId
      products[0].trackInventory     default: 1 if barCode or isSupply, else 0
      products[0].userId             author of the stock movement (sp_inventory_post)
      productDetails[0].stockQuantity  target count → 'opening' / 'adjustment' movement
      productOptions[].type          radio (pick one) | checkbox (pick many)
      productOptions[].optionChoices[].unit  measurement prefix (g, kg, ml, L, pz) if no measurementId
    Options and choices are replaced in full on every insert/update.

    DECLARE @pjsonfile NVARCHAR(MAX) = N'{
        "products": [
            {
                "action": 1,
                "productId": null,
                "companyId": 1,
                "userId": 1,
                "name": "Té Arizona",
                "barCode": "613008715861",
                "dateOfExpire": "2027-03-12",
                "noExpire": 0,
                "productFormId": null,
                "manufactureId": null,
                "description": "",
                "productCategoryId": 3,
                "isSupply": 0,
                "netContent": 680,
                "unitOfMeasure": "ml",
                "referencePrice": 25.00,
                "trackInventory": 1,
                "isActive": 1
            }
        ],
        "productDetails": [
            { "stockQuantity": 24, "unitPrice": 18.50, "salePrice": 25.00 }
        ],
        "productDescriptions": [
            { "Dosage": "", "measurementId": null, "is_principal": 1, "activeIngredientId": null }
        ],
        "productOptions": [
            {
                "optionKey": "sabor",
                "name": "Sabor",
                "type": "radio",
                "isRequired": 1,
                "optionChoices": [
                    { "choiceKey": "negro", "name": "Negro", "price": 0, "description": "", "quantity": 600, "unit": "ml" },
                    { "choiceKey": "mango", "name": "Mango", "price": 2.00, "description": "", "quantity": 450, "measurementId": null, "unit": "ml" }
                ]
            }
        ]
    }';
    EXEC dbo.sp_products @pjsonfile = @pjsonfile;
    */

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
            SELECT JSON_VALUE(value, '$.value') AS [value], JSON_VALUE(value, '$.msg') AS [msg], JSON_VALUE(value, '$.error') AS [error] FROM OPENJSON(@Outputmessage, '$.result')
            FOR JSON PATH, ROOT('result'), INCLUDE_NULL_VALUES;
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

    -- Return Status Response: ONE JSON document {"result":[{value,msg,error}]}.
    -- execute_sp_json (modules/products.py) joins column 0 of every row: a plain
    -- rowset reached the client as the bare id, and errors (value='') as {"result":[]}.
    SELECT JSON_VALUE(value, '$.value') AS [value], JSON_VALUE(value, '$.msg') AS [msg], JSON_VALUE(value, '$.error') AS [error] FROM OPENJSON(@Outputmessage, '$.result')
    FOR JSON PATH, ROOT('result'), INCLUDE_NULL_VALUES;
END
GO
