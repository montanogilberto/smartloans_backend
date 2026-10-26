-- =============================================================================
-- Products P0: soft delete, supplies/inactive in the admin list, nested wizard
-- payload, imageUrl, product form/packing, longer technical description
-- =============================================================================
-- Run manually against the live DB (no migration runner). Re-runnable: guarded
-- ALTERs + CREATE OR ALTER. Run AFTER 2026-10-26_products_unify_sp_products.sql.
-- Deploy order: 1) this file  2) frontend (POSVending /products-management +
-- ProductWizard). The old frontend keeps working against the new SPs.
--
-- WHY (live schema checked 2026-10-26):
--   * The POS frontend (ProductContext → POST /products) nests productDetails,
--     productDescriptions, productOptions and productForm INSIDE products[0], but
--     sp_products only read them from the JSON root. Wizard saves dropped prices,
--     stock, descriptions and options, and an UPDATE deleted every option of the
--     product (step 4 deletes, then inserted zero rows).
--   * action 3 hard-deleted the product. There are no FKs to dbo.products, so
--     purchase/sale history was orphaned. dbo.products.isActive already exists.
--   * sp_products_by_company always hid isSupply products, so supplies created
--     from a ticket (Nuevo Egreso) could never be edited or removed in
--     /products-management; inactive ones could not be reactivated either.
--   * dbo.products had no imageUrl column: the wizard uploaded the photo to blob
--     storage and the URL was dropped.
--   * sp_products_one (the wizard's edit/view load) did not return netContent,
--     unitOfMeasure, referencePrice: the next save cleared them (update writes
--     those three as "null = cleared").
--   * productsDescription.Dosage is VARCHAR(50): a longer "Descripción técnica"
--     failed the whole product save (string truncation).
--
-- WHAT:
--   1. dbo.products.imageUrl NVARCHAR(500) NULL.
--   2. dbo.productsDescription.Dosage → NVARCHAR(500) NULL.
--   3. dbo.sp_products
--      - productDetails/productDescriptions/productOptions/productForm read from
--        the root OR products[0] (root wins); a single object becomes [object].
--      - On update, descriptions/options are replaced only when the key is sent,
--        so partial callers no longer wipe them.
--      - action 3 = deactivate (isActive = 0), action 4 = reactivate. No hard delete.
--      - imageUrl saved (update: missing/empty keeps the current one).
--      - productForm {quantity, packingName, packingPresentationName} saved into
--        dbo.productForms (+ find-or-create packing type / presentation by name);
--        all three empty clears products.productFormId.
--   4. dbo.sp_products_by_company: optional includeSupplies (admin screens); returns
--      isSupply and imageUrl. The POS never sends the flag → same output as before.
--   5. dbo.sp_products_one: + netContent, unitOfMeasure, referencePrice, isSupply,
--      imageUrl and a form object (quantity + packing names).
--   6. dbo.sp_products_all: only active products — a deactivated product must not
--      be matched by the ticket agent or offered in Nuevo Egreso (same visibility
--      the old hard delete had).
--
-- Unchanged on purpose: the `@companyId <> 1` guard in sp_products (separate fix).
-- ROLLBACK: 2026-10-26c_products_soft_delete_nested_payload_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- 1) products.imageUrl ------------------------------------------------------------------
IF COL_LENGTH('dbo.products', 'imageUrl') IS NULL
    ALTER TABLE dbo.products ADD imageUrl NVARCHAR(500) NULL;
GO

-- 2) productsDescription.Dosage → NVARCHAR(500) ----------------------------------------
IF EXISTS (SELECT 1 FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
           WHERE c.object_id = OBJECT_ID('dbo.productsDescription') AND c.name = 'Dosage'
             AND NOT (t.name = 'nvarchar' AND c.max_length = 1000))
    ALTER TABLE dbo.productsDescription ALTER COLUMN Dosage NVARCHAR(500) NULL;
GO

-- 3) dbo.sp_products ---------------------------------------------------------------------
CREATE OR ALTER PROC [dbo].[sp_products]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    action: 1 = insert, 2 = update, 3 = deactivate (isActive = 0), 4 = reactivate.
    Every key except action and companyId is optional; on update a missing key keeps
    the current value (except netContent / unitOfMeasure / referencePrice: null clears
    them). productDetails / productDescriptions / productOptions / productForm may sit
    at the root (below) or inside products[0] (what the POS app sends).
      products[0].productId          required for 2, 3 and 4; ignored on insert
      products[0].code               not read: auto-assigned MAX(code) + 1 per company
      products[0].noExpire           update only: 1 clears dateOfExpire
      products[0].productCategoryId  alias: categoryId
      products[0].trackInventory     default: 1 if barCode or isSupply, else 0
      products[0].userId             author of the stock movement (sp_inventory_post)
      products[0].imageUrl           blob URL from POST /products/upload-image; missing keeps it
      productDetails[0].stockQuantity  target count → 'opening' / 'adjustment' movement
      productOptions[].type          radio (pick one) | checkbox (pick many)
      productOptions[].optionChoices[].unit  measurement prefix (g, kg, ml, L, pz) if no measurementId
      productForm                    { quantity, packingName, packingPresentationName }; all empty clears it
    On update, descriptions and options are replaced in full only when their key is sent.

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
                "manufactureId": null,
                "description": "",
                "productCategoryId": 3,
                "isSupply": 0,
                "netContent": 680,
                "unitOfMeasure": "ml",
                "referencePrice": 25.00,
                "imageUrl": null,
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
        "productForm": { "quantity": "680 ml", "packingName": "Lata", "packingPresentationName": "Individual" },
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
        @productId INT,
        @oldFormId INT,
        @details NVARCHAR(MAX),
        @descriptions NVARCHAR(MAX),
        @options NVARCHAR(MAX),
        @form NVARCHAR(MAX);

    BEGIN TRY
        -- 1. Extract Root Context
        SELECT TOP (1)
            @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
            @companyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
            @productId = TRY_CAST(JSON_VALUE(value, '$.productId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.products');

        -- Child sections: root first, else nested in products[0] (the POS app's shape).
        -- JSON_QUERY returns NULL when the key is missing, so NULL = "not sent".
        SET @details      = COALESCE(JSON_QUERY(@pjsonfile, '$.productDetails'),      JSON_QUERY(@pjsonfile, '$.products[0].productDetails'));
        SET @descriptions = COALESCE(JSON_QUERY(@pjsonfile, '$.productDescriptions'), JSON_QUERY(@pjsonfile, '$.products[0].productDescriptions'));
        SET @options      = COALESCE(JSON_QUERY(@pjsonfile, '$.productOptions'),      JSON_QUERY(@pjsonfile, '$.products[0].productOptions'));
        SET @form         = COALESCE(JSON_QUERY(@pjsonfile, '$.productForm'),         JSON_QUERY(@pjsonfile, '$.products[0].productForm'));
        -- A single object is treated as a one-element array.
        IF LEFT(LTRIM(@details), 1) = '{'      SET @details      = N'[' + @details + N']';
        IF LEFT(LTRIM(@descriptions), 1) = '{' SET @descriptions = N'[' + @descriptions + N']';
        IF LEFT(LTRIM(@options), 1) = '{'      SET @options      = N'[' + @options + N']';

        -- Validations
        IF @action IS NULL RAISERROR('action is required (1=insert, 2=update, 3=deactivate, 4=reactivate).', 16, 1);
        IF @action NOT IN (1, 2, 3, 4) RAISERROR('action must be 1=insert, 2=update, 3=deactivate or 4=reactivate.', 16, 1);
        IF @companyId IS NULL RAISERROR('companyId is required.', 16, 1);
        IF @companyId <> 1 RAISERROR('Invalid companyId.', 16, 1);
        IF @action IN (2, 3, 4) AND @productId IS NULL RAISERROR('productId is required for update, deactivate and reactivate.', 16, 1);

        BEGIN TRANSACTION;

        /* ============================================================
           STEP 0: DEACTIVATE / REACTIVATE (soft delete — history stays linked)
           ============================================================ */
        IF @action IN (3, 4)
        BEGIN
            UPDATE dbo.products
            SET isActive = CASE WHEN @action = 4 THEN 1 ELSE 0 END,
                updatedAt = GETDATE()
            WHERE productId = @productId AND companyId = @companyId;

            IF @@ROWCOUNT = 0 RAISERROR('Product not found for this company.', 16, 1);

            COMMIT TRANSACTION;

            SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@productId AS NVARCHAR(50))), '$.result[0].msg',
                                 CASE WHEN @action = 4 THEN 'Reactivated Successfully' ELSE 'Deactivated Successfully' END);
            SELECT JSON_VALUE(value, '$.value') AS [value], JSON_VALUE(value, '$.msg') AS [msg], JSON_VALUE(value, '$.error') AS [error] FROM OPENJSON(@Outputmessage, '$.result')
            FOR JSON PATH, ROOT('result'), INCLUDE_NULL_VALUES;
            RETURN;
        END

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

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, productCategoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice, imageUrl, trackInventory, isActive)
            SELECT
                JSON_VALUE(value, '$.name'), JSON_VALUE(value, '$.barCode'), @nextCode,
                TRY_CONVERT(DATE, NULLIF(JSON_VALUE(value, '$.dateOfExpire'), '')), TRY_CAST(JSON_VALUE(value, '$.productFormId') AS INT),
                TRY_CAST(JSON_VALUE(value, '$.manufactureId') AS INT), JSON_VALUE(value, '$.description'),
                GETDATE(), TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'), JSON_VALUE(value, '$.categoryId')) AS INT), @companyId,
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isSupply') AS BIT), 0),
                TRY_CAST(JSON_VALUE(value, '$.netContent') AS DECIMAL(10,3)), NULLIF(JSON_VALUE(value, '$.unitOfMeasure'), ''),
                TRY_CAST(JSON_VALUE(value, '$.referencePrice') AS DECIMAL(10,2)),
                NULLIF(JSON_VALUE(value, '$.imageUrl'), ''),
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
            SELECT @oldFormId = productFormId FROM dbo.products WHERE productId = @productId AND companyId = @companyId;

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
                p.imageUrl = COALESCE(NULLIF(JSON_VALUE(j.value, '$.imageUrl'), ''), p.imageUrl),
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

            IF @@ROWCOUNT = 0 RAISERROR('Product not found for this company.', 16, 1);
        END

        /* ============================================================
           STEP 1b: PRODUCT FORM (quantity + packing type + presentation)
           ============================================================ */
        IF @form IS NOT NULL
        BEGIN
            DECLARE @formQty VARCHAR(50)  = LEFT(LTRIM(RTRIM(ISNULL(JSON_VALUE(@form, '$.quantity'), ''))), 50),
                    @packName VARCHAR(50) = LEFT(LTRIM(RTRIM(ISNULL(JSON_VALUE(@form, '$.packingName'), ''))), 50),
                    @presName VARCHAR(50) = LEFT(LTRIM(RTRIM(ISNULL(JSON_VALUE(@form, '$.packingPresentationName'), ''))), 50),
                    @packId INT, @presId INT, @formId INT;

            IF @formQty = '' AND @packName = '' AND @presName = ''
            BEGIN
                UPDATE dbo.products SET productFormId = NULL WHERE productId = @productId;
            END
            ELSE
            BEGIN
                -- Packing type / presentation are shared lookups: find by name, else create.
                SELECT TOP (1) @packId = productsPackingTypeId FROM dbo.productsPackingType
                WHERE ISNULL(name, '') = @packName ORDER BY productsPackingTypeId;
                IF @packId IS NULL
                BEGIN
                    INSERT INTO dbo.productsPackingType (name) VALUES (@packName);
                    SET @packId = SCOPE_IDENTITY();
                END

                SELECT TOP (1) @presId = productPackingPresentationId FROM dbo.productsPackingPresentation
                WHERE ISNULL(name, '') = @presName ORDER BY productPackingPresentationId;
                IF @presId IS NULL
                BEGIN
                    INSERT INTO dbo.productsPackingPresentation (name) VALUES (@presName);
                    SET @presId = SCOPE_IDENTITY();
                END

                -- Reuse this product's own form row; never edit one another product shares.
                IF @oldFormId IS NOT NULL
                   AND EXISTS (SELECT 1 FROM dbo.productForms WHERE productFormId = @oldFormId)
                   AND NOT EXISTS (SELECT 1 FROM dbo.products WHERE productFormId = @oldFormId AND productId <> @productId)
                BEGIN
                    UPDATE dbo.productForms
                    SET quantity = @formQty, productPackingPresentationId = @presId, productsPackingTypeId = @packId
                    WHERE productFormId = @oldFormId;
                    SET @formId = @oldFormId;
                END
                ELSE
                BEGIN
                    INSERT INTO dbo.productForms (quantity, productPackingPresentationId, productsPackingTypeId)
                    VALUES (@formQty, @presId, @packId);
                    SET @formId = SCOPE_IDENTITY();
                END

                UPDATE dbo.products SET productFormId = @formId WHERE productId = @productId;
            END
        END

        /* ============================================================
           STEP 2: PRODUCT DETAILS (Simple IF EXISTS Check)
           ============================================================ */
        DECLARE @stock INT, @uPrice DECIMAL(10,2), @sPrice DECIMAL(10,2);

        SELECT TOP (1)
            @stock = TRY_CAST(JSON_VALUE(value, '$.stockQuantity') AS INT),
            @uPrice = TRY_CAST(JSON_VALUE(value, '$.unitPrice') AS DECIMAL(10,2)),
            @sPrice = TRY_CAST(JSON_VALUE(value, '$.salePrice') AS DECIMAL(10,2))
        FROM OPENJSON(@details);

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
           STEP 3: PRODUCT DESCRIPTIONS (replaced only when sent)
           ============================================================ */
        IF OBJECT_ID('dbo.productsDescription', 'U') IS NOT NULL AND @descriptions IS NOT NULL
        BEGIN
            DELETE FROM dbo.productsDescription WHERE productId = @productId;

            INSERT INTO dbo.productsDescription (productId, Dosage, measurementId, is_principal, activeIngredientId)
            SELECT
                @productId, JSON_VALUE(value, '$.Dosage'),
                TRY_CAST(JSON_VALUE(value, '$.measurementId') AS INT),
                JSON_VALUE(value, '$.is_principal'),
                TRY_CAST(JSON_VALUE(value, '$.activeIngredientId') AS INT)
            FROM OPENJSON(@descriptions);
        END

        /* ============================================================
           STEP 4: OPTIONS AND CHOICES (replaced in full only when sent)
           ============================================================ */
        IF @options IS NOT NULL
        BEGIN
            DELETE FROM dbo.productOptionChoices WHERE productOptionId IN (SELECT productOptionId FROM dbo.productOptions WHERE productId = @productId);
            DELETE FROM dbo.productOptions WHERE productId = @productId;

            -- Loop over the array index to keep option/choice identities paired
            DECLARE @index INT = 0, @maxOptions INT;
            SET @maxOptions = (SELECT COUNT(*) FROM OPENJSON(@options));

            WHILE @index < @maxOptions
            BEGIN
                DECLARE @optPath NVARCHAR(100) = '$[' + CAST(@index AS NVARCHAR(10)) + ']';
                DECLARE @newOptId INT;

                -- Insert the Option Node
                INSERT INTO dbo.productOptions (productId, optionKey, name, type, isRequired, createdAt, updatedAt)
                SELECT @productId, JSON_VALUE(@options, @optPath + '.optionKey'), JSON_VALUE(@options, @optPath + '.name'), JSON_VALUE(@options, @optPath + '.type'),
                       ISNULL(TRY_CAST(JSON_VALUE(@options, @optPath + '.isRequired') AS BIT), 0), GETDATE(), GETDATE();

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
                FROM OPENJSON(@options, @optPath + '.optionChoices');

                SET @index = @index + 1;
            END
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

-- 4) dbo.sp_products_by_company ----------------------------------------------------------
CREATE OR ALTER PROC [dbo].[sp_products_by_company]
   @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1" } ] }'                         -- all (POS)
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1", "categoryId": "1002" } ] }'  -- one category
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1", "includeInactive": 1, "includeSupplies": 1 } ] }'  -- admin
    */

    DECLARE @companyId INT;
    DECLARE @categoryId INT;
    DECLARE @includeInactive BIT;
    DECLARE @includeSupplies BIT;

    SET @companyId = CAST(
        (SELECT JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.products')) AS INT
    );

    -- Optional: productCategoryId (or legacy "categoryId"); missing/0 = all categories.
    SELECT TOP (1)
        @categoryId = NULLIF(TRY_CAST(COALESCE(JSON_VALUE(value, '$.productCategoryId'),
                                               JSON_VALUE(value, '$.categoryId')) AS INT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    -- Admin screens send includeInactive / includeSupplies = 1 to see (and reactivate /
    -- edit) hidden products; the POS never does, so its menu is unchanged.
    SELECT TOP (1)
        @includeInactive = ISNULL(TRY_CAST(JSON_VALUE(value, '$.includeInactive') AS BIT), 0),
        @includeSupplies = ISNULL(TRY_CAST(JSON_VALUE(value, '$.includeSupplies') AS BIT), 0)
    FROM OPENJSON(@pjsonfile, '$.products');

    SELECT
        p.productId AS [id],
        p.productId,
        p.name,
        p.description,
        ISNULL(pd.salePrice, 0) AS price,
        NULL AS [image],
        p.imageUrl,
        p.productCategoryId AS categoryId,
        ISNULL(p.code, '') AS code,
        ISNULL(p.barCode, '') AS barCode,
        p.dateOfExpire,
        p.netContent,
        p.unitOfMeasure,
        p.referencePrice,
        p.companyId,
        p.isSupply,
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
      AND (ISNULL(p.isSupply, 0) = 0 OR @includeSupplies = 1)
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

-- 5) dbo.sp_products_one -----------------------------------------------------------------
CREATE OR ALTER PROC [dbo].[sp_products_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "productId": "1" } ] }'
    */

    DECLARE @productId INT;

    -- Extracting ProductId safely
    SET @productId = TRY_CAST((SELECT JSON_VALUE(value, '$.productId') FROM OPENJSON(@pjsonfile, '$.products')) AS INT);

    -- Every column the wizard edits must come back here: the next save writes
    -- netContent / unitOfMeasure / referencePrice as sent (null = cleared).
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
        ,p.[netContent]
        ,p.[unitOfMeasure]
        ,p.[referencePrice]
        ,p.[imageUrl]
        ,p.[isSupply]
        ,p.[trackInventory]
        ,p.[isActive]
        ,ISNULL(inv.stockQuantity, 0) AS stockQuantity
        ,p.[createdAt]
        ,ISNULL(p.[updatedAt],'') AS updatedAt

        -- 0. Product form: quantity + packing type / presentation names
        ,JSON_QUERY((
            SELECT f.productFormId, f.quantity, f.productPackingPresentationId, f.productsPackingTypeId,
                   ISNULL(pt.name, '') AS packingName, ISNULL(pp.name, '') AS packingPresentationName
            FROM dbo.productForms f
            LEFT JOIN dbo.productsPackingType pt ON pt.productsPackingTypeId = f.productsPackingTypeId
            LEFT JOIN dbo.productsPackingPresentation pp ON pp.productPackingPresentationId = f.productPackingPresentationId
            WHERE f.productFormId = p.productFormId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        )) AS form

        -- 1. Nested Details Object (Returns as an array/object matching your save logic)
        ,(
            SELECT
                pd.productDetailId
                ,ISNULL(inv.stockQuantity, 0) AS stockQuantity
                ,pd.unitPrice
                ,pd.salePrice
            FROM dbo.productDetails pd
            WHERE pd.productId = p.productId
            FOR JSON PATH
        ) AS productDetails

        -- 2. Nested Descriptions Array
        ,(
            SELECT
                pdesc.productDescriptionId
                ,pdesc.Dosage
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

-- 6) dbo.sp_products_all: active products only -------------------------------------------
CREATE OR ALTER PROC [dbo].[sp_products_all]
AS
SET NOCOUNT ON

BEGIN

    -- Callers: GET /all_products → ticket agent product matching (LoanAgents
    -- tools/backend_api.list_products) and Nuevo Egreso (getCompanyProducts).
    -- A deactivated product is hidden from both, as the old hard delete did.
    SELECT
        [productId]
        ,[name]
        ,ISNULL([barCode],'') AS barCode
        ,ISNULL([code],'') AS code
        ,ISNULL([dateOfExpire],'') AS dateOfExpire
        ,[productFormId]
        ,[manufactureId]
        ,ISNULL([description],'') AS description
        ,[createdAt]
        ,ISNULL([updatedAt],'') AS updatedAt
        ,companyId
        ,isSupply
        ,netContent
        ,unitOfMeasure
        ,referencePrice
    FROM [dbo].[products]
    WHERE isActive = 1
    FOR JSON AUTO, ROOT('products');

END
GO

-- Verify --------------------------------------------------------------------------------
SELECT
    CASE WHEN COL_LENGTH('dbo.products', 'imageUrl') IS NOT NULL THEN 1 ELSE 0 END AS hasImageUrl,
    COL_LENGTH('dbo.productsDescription', 'Dosage') AS dosageBytes,  -- 1000 = NVARCHAR(500)
    CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products')) LIKE '%products[0].productDetails%'
          AND OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products')) LIKE '%Deactivated Successfully%' THEN 1 ELSE 0 END AS spProductsP0,
    CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products_by_company')) LIKE '%includeSupplies%' THEN 1 ELSE 0 END AS byCompanyFlags,
    CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products_one')) LIKE '%packingPresentationName%' THEN 1 ELSE 0 END AS oneHasForm,
    CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products_all')) LIKE '%isActive = 1%' THEN 1 ELSE 0 END AS allActiveOnly;
GO
