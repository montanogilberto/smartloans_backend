-- =============================================================================
-- Inventory phase 1: stable option/choice ids, products.stockUnit (pz | ml | g),
-- purchases and sales posted in the stock unit
-- =============================================================================
-- Design: POSVending docs/inventory-portions-design.md (§4.1, §4.3, §5.1, §5.2, §9).
-- Run manually against the live DB (no migration runner). Re-runnable: guarded ALTERs
-- + CREATE OR ALTER. Run AFTER 2026-10-26c_products_soft_delete_nested_payload.sql.
-- Deploy order: 1) this file  2) POSVending (wizard sends stableOptionIds + ids +
-- stockUnit). The app in production keeps working with this SP (§ "Old app" below).
--
-- WHY:
--   * sp_products deleted and re-inserted every option and choice on each save: the
--     ids changed every time, history lost its link (incomeDetailOptions already has
--     an orphan) and phase 2 consumption rules ("Jabón › Ariel consumes 100 ml") would
--     be wiped on every save.
--   * Supplies sold by portion must be counted in ml/g: an 8 L Ariel is 8000 ml, a
--     portion is 100 ml. Today inventory only counts pieces.
--
-- WHAT:
--   1. productOptions.isActive / productOptionChoices.isActive BIT NOT NULL DEFAULT 1.
--   2. products.stockUnit VARCHAR(10) NOT NULL DEFAULT 'pz', CHECK IN ('pz','ml','g').
--      Every existing product stays 'pz' → nothing changes until a product is switched.
--   3. dbo.fn_convertQuantity (ml↔L, g↔kg, mg→g; same unit = same number; else NULL)
--      and dbo.fn_stockFactor(productId): how many stock units one piece is
--      ('pz' → 1; 'ml' with netContent 8 L → 8000; not convertible → NULL).
--   4. dbo.sp_products:
--      - options/choices UPSERTED by id (only with products[0].stableOptionIds = 1);
--        a row left out is deleted if no history uses it (incomeDetailOptions,
--        expenseDetailOptions, orderDetails, laundryDeviceUses), else isActive = 0.
--      - stockUnit read on insert/update; ml/g requires a convertible netContent;
--        changing the unit of a product with stock posts a 'unit_change' movement
--        (balance ÷ old factor × new factor).
--   5-8. Menu readers hide inactive options/choices and return the ids + stockUnit:
--        sp_products_by_company, sp_products_one, sp_products_food,
--        sp_laundryDevices (action 7, a device's cycles). History readers (sp_income,
--        tickets, orders, rewards, discounts) are untouched: they resolve by id, and
--        deactivated rows still exist.
--        sp_products_one also requires products[0].companyId and only returns that
--        company's product (before, any productId was returned to any caller).
--   9-10. trg_expenseDetails_inventory / trg_incomeDetails_inventory post
--        quantity × fn_stockFactor (identical to today for 'pz' products).
--
-- Old app (production frontend, before this deploy) maps existing ids BY POSITION; if
-- the SP honored them, deleting option 1 would overwrite its row with option 2 and
-- past sales would show the wrong name. Without stableOptionIds the SP ignores the
-- ids: every row is inserted, and the previous rows are deleted/deactivated — never
-- worse than today, which deleted them outright.
--
-- Not changed: one_products (reads tables that do not exist; no caller),
-- sp_orders_all / sp_orders_one (legacy food-order listing).
-- ROLLBACK: 2026-10-27b_inventory_phase1_stable_options_stock_unit_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- 1) isActive on options and choices ----------------------------------------------------
IF COL_LENGTH('dbo.productOptions', 'isActive') IS NULL
    ALTER TABLE dbo.productOptions ADD isActive BIT NOT NULL CONSTRAINT DF_productOptions_isActive DEFAULT (1);
GO
IF COL_LENGTH('dbo.productOptionChoices', 'isActive') IS NULL
    ALTER TABLE dbo.productOptionChoices ADD isActive BIT NOT NULL CONSTRAINT DF_productOptionChoices_isActive DEFAULT (1);
GO

-- 2) products.stockUnit ------------------------------------------------------------------
IF COL_LENGTH('dbo.products', 'stockUnit') IS NULL
    ALTER TABLE dbo.products ADD stockUnit VARCHAR(10) NOT NULL CONSTRAINT DF_products_stockUnit DEFAULT ('pz');
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_products_stockUnit')
    ALTER TABLE dbo.products WITH CHECK ADD CONSTRAINT CK_products_stockUnit CHECK (stockUnit IN ('pz', 'ml', 'g'));
GO

-- 3) Unit conversion ----------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.fn_convertQuantity (@qty DECIMAL(18,6), @fromUnit VARCHAR(10), @toUnit VARCHAR(10))
RETURNS DECIMAL(18,6)
AS
BEGIN
    -- ml↔L and g↔kg (mg → g); the same unit returns the number; anything else NULL
    -- ("can't convert" is reported by the caller, never guessed).
    DECLARE @f VARCHAR(10) = LOWER(LTRIM(RTRIM(@fromUnit))), @t VARCHAR(10) = LOWER(LTRIM(RTRIM(@toUnit)));
    IF @qty IS NULL OR @f IS NULL OR @t IS NULL RETURN NULL;
    IF @f = @t RETURN @qty;
    RETURN CASE
        WHEN @f = 'l'  AND @t = 'ml' THEN @qty * 1000
        WHEN @f = 'ml' AND @t = 'l'  THEN @qty / 1000
        WHEN @f = 'kg' AND @t = 'g'  THEN @qty * 1000
        WHEN @f = 'g'  AND @t = 'kg' THEN @qty / 1000
        WHEN @f = 'mg' AND @t = 'g'  THEN @qty / 1000
        ELSE NULL
    END;
END
GO

CREATE OR ALTER FUNCTION dbo.fn_stockFactor (@productId INT)
RETURNS DECIMAL(18,6)
AS
BEGIN
    -- Stock units in ONE piece of the product: 'pz' → 1; 'ml' with netContent 8 L →
    -- 8000; NULL when the content is missing or not convertible to the stock unit.
    DECLARE @unit VARCHAR(10), @content DECIMAL(18,6), @contentUnit VARCHAR(10);
    SELECT @unit = stockUnit, @content = netContent, @contentUnit = unitOfMeasure
    FROM dbo.products WHERE productId = @productId;
    IF @unit IS NULL OR @unit = 'pz' RETURN 1;
    IF ISNULL(@content, 0) <= 0 RETURN NULL;
    RETURN dbo.fn_convertQuantity(@content, @contentUnit, @unit);
END
GO

-- 4) dbo.sp_products ----------------------------------------------------------------------
CREATE OR ALTER PROC [dbo].[sp_products]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    action: 1 = insert, 2 = update, 3 = deactivate (isActive = 0), 4 = reactivate.
    stockUnit: what inventoryStock counts for this product — 'pz' (default), or 'ml' / 'g'
      for supplies dispensed by portion (needs netContent in ml/L or g/kg). Changing it on
      a product with stock converts the balance (1 × 8 L → 8000 ml, 'unit_change').
    Options/choices are upserted by id when products[0].stableOptionIds = 1 (the wizard
      sends each row's own productOptionId / productOptionChoiceId); without the flag every
      row is new. A row left out of the payload is DELETED if no history uses it, else
      deactivated (isActive = 0) so sales, tickets and orders keep resolving it.
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
    On update, descriptions are replaced, and options upserted, only when their key is sent.

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
                "isActive": 1,
                "stockUnit": "pz",
                "stableOptionIds": 1
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
        @oldUnit VARCHAR(10),
        @oldFactor DECIMAL(18,6),
        @stableIds BIT = 0,
        @details NVARCHAR(MAX),
        @descriptions NVARCHAR(MAX),
        @options NVARCHAR(MAX),
        @form NVARCHAR(MAX);

    BEGIN TRY
        -- 1. Extract Root Context
        SELECT TOP (1)
            @action = TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
            @companyId = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
            @productId = TRY_CAST(JSON_VALUE(value, '$.productId') AS INT),
            @stableIds = ISNULL(TRY_CAST(JSON_VALUE(value, '$.stableOptionIds') AS BIT), 0)
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

            INSERT INTO dbo.products (name, barCode, code, dateOfExpire, productFormId, manufactureId, description, createdAt, productCategoryId, companyId, isSupply, netContent, unitOfMeasure, referencePrice, imageUrl, trackInventory, isActive, stockUnit)
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
                ISNULL(TRY_CAST(JSON_VALUE(value, '$.isActive') AS BIT), 1),
                COALESCE(NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.stockUnit'))), ''), 'pz')
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @productId = SCOPE_IDENTITY();
        END
        ELSE IF @action = 2
        BEGIN
            SELECT @oldFormId = productFormId, @oldUnit = stockUnit, @oldFactor = dbo.fn_stockFactor(productId)
            FROM dbo.products WHERE productId = @productId AND companyId = @companyId;

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
                p.isActive = COALESCE(TRY_CAST(JSON_VALUE(j.value, '$.isActive') AS BIT), p.isActive),
                p.stockUnit = COALESCE(NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.stockUnit'))), ''), p.stockUnit)
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
           STEP 1c: STOCK UNIT (pz | ml | g)
           ============================================================ */
        -- Counting in ml/g needs a content convertible to that unit (8 L → 8000 ml).
        IF EXISTS (SELECT 1 FROM dbo.products WHERE productId = @productId AND stockUnit <> 'pz')
           AND dbo.fn_stockFactor(@productId) IS NULL
            RAISERROR('Para contar el inventario en ml o g, captura el contenido neto del producto en ml/L o g/kg.', 16, 1);

        -- Unit changed on a product with stock: convert the balance through pieces
        -- (pz → ml: 1 bottle of 8 L = 8000 ml). Posted before step 2, so a stock count
        -- typed in the same save is read in the NEW unit.
        IF @action = 2 AND @oldUnit IS NOT NULL
        BEGIN
            DECLARE @newUnit VARCHAR(10), @newFactor DECIMAL(18,6), @balance DECIMAL(18,3);
            SELECT @newUnit = stockUnit, @newFactor = dbo.fn_stockFactor(productId)
            FROM dbo.products WHERE productId = @productId;

            IF @newUnit <> @oldUnit
            BEGIN
                SELECT @balance = stockQuantity FROM dbo.inventoryStock WITH (UPDLOCK, HOLDLOCK)
                WHERE companyId = @companyId AND productId = @productId;

                IF ISNULL(@balance, 0) <> 0
                BEGIN
                    IF @oldFactor IS NULL OR @newFactor IS NULL
                        RAISERROR('No se puede convertir el inventario a la nueva unidad: revisa el contenido neto.', 16, 1);
                    DECLARE @unitDelta DECIMAL(18,3) = ROUND(@balance / @oldFactor * @newFactor, 3) - @balance;
                    DECLARE @unitNote NVARCHAR(300) = CONCAT(N'Unidad de inventario: ', @oldUnit, N' → ', @newUnit);
                    EXEC dbo.sp_inventory_post
                        @companyId = @companyId, @productId = @productId, @quantityDelta = @unitDelta,
                        @reason = 'unit_change', @refType = 'product_save', @refId = @productId,
                        @userId = NULL, @notes = @unitNote;
                END
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
           STEP 4: OPTIONS AND CHOICES (upserted only when sent)
           ============================================================ */
        -- Ids are stable across saves (sales, tickets, orders and future consumption
        -- rules point at them). An id is honored only with stableOptionIds = 1 and only
        -- if it belongs to this product/option; anything else is inserted as new.
        IF @options IS NOT NULL
        BEGIN
            DECLARE @keptOptions TABLE (productOptionId INT PRIMARY KEY);
            DECLARE @keptChoices TABLE (productOptionChoiceId INT PRIMARY KEY);
            DECLARE @payloadChoices TABLE (
                ord INT NOT NULL, choiceId INT NULL, choiceKey NVARCHAR(255) NULL, name NVARCHAR(255) NULL,
                price DECIMAL(10,2) NOT NULL, description NVARCHAR(MAX) NULL, quantity DECIMAL(10,3) NULL, measurementId INT NULL);
            DECLARE @index INT = 0, @maxOptions INT = (SELECT COUNT(*) FROM OPENJSON(@options));

            WHILE @index < @maxOptions
            BEGIN
                DECLARE @optPath NVARCHAR(100) = '$[' + CAST(@index AS NVARCHAR(10)) + ']';
                DECLARE @optId INT = CASE WHEN @stableIds = 1
                    THEN TRY_CAST(JSON_VALUE(@options, @optPath + '.productOptionId') AS INT) END;

                IF @optId IS NOT NULL
                   AND (NOT EXISTS (SELECT 1 FROM dbo.productOptions WHERE productOptionId = @optId AND productId = @productId)
                        OR EXISTS (SELECT 1 FROM @keptOptions WHERE productOptionId = @optId))
                    SET @optId = NULL;

                IF @optId IS NOT NULL
                    UPDATE dbo.productOptions
                    SET optionKey = JSON_VALUE(@options, @optPath + '.optionKey'),
                        name = JSON_VALUE(@options, @optPath + '.name'),
                        type = JSON_VALUE(@options, @optPath + '.type'),
                        isRequired = ISNULL(TRY_CAST(JSON_VALUE(@options, @optPath + '.isRequired') AS BIT), 0),
                        isActive = 1,
                        updatedAt = GETDATE()
                    WHERE productOptionId = @optId;
                ELSE
                BEGIN
                    INSERT INTO dbo.productOptions (productId, optionKey, name, type, isRequired, isActive, createdAt, updatedAt)
                    SELECT @productId, JSON_VALUE(@options, @optPath + '.optionKey'), JSON_VALUE(@options, @optPath + '.name'),
                           JSON_VALUE(@options, @optPath + '.type'),
                           ISNULL(TRY_CAST(JSON_VALUE(@options, @optPath + '.isRequired') AS BIT), 0), 1, GETDATE(), GETDATE();
                    SET @optId = SCOPE_IDENTITY();
                END
                INSERT INTO @keptOptions (productOptionId) VALUES (@optId);

                -- Choices of this option, as sent. quantity + unit per choice (19 L, 600 ml):
                -- measurementId, or the unit code resolved against dbo.measurements.prefix.
                DELETE FROM @payloadChoices;
                INSERT INTO @payloadChoices (ord, choiceId, choiceKey, name, price, description, quantity, measurementId)
                SELECT CAST([key] AS INT),
                       CASE WHEN @stableIds = 1 THEN TRY_CAST(JSON_VALUE(value, '$.productOptionChoiceId') AS INT) END,
                       JSON_VALUE(value, '$.choiceKey'),
                       JSON_VALUE(value, '$.name'),
                       COALESCE(TRY_CAST(JSON_VALUE(value, '$.price') AS DECIMAL(10,2)), 0.00),
                       COALESCE(JSON_VALUE(value, '$.description'), ''),
                       TRY_CAST(JSON_VALUE(value, '$.quantity') AS DECIMAL(10,3)),
                       COALESCE(TRY_CAST(JSON_VALUE(value, '$.measurementId') AS INT),
                                (SELECT TOP (1) m.measurementId FROM dbo.measurements m
                                 WHERE m.prefix = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.unit'))), '')))
                FROM OPENJSON(@options, @optPath + '.optionChoices');

                -- An id from another option, or repeated in the payload, is not honored.
                UPDATE pc SET choiceId = NULL FROM @payloadChoices pc
                WHERE pc.choiceId IS NOT NULL
                  AND (NOT EXISTS (SELECT 1 FROM dbo.productOptionChoices c
                                   WHERE c.productOptionChoiceId = pc.choiceId AND c.productOptionId = @optId)
                       OR EXISTS (SELECT 1 FROM @payloadChoices o WHERE o.choiceId = pc.choiceId AND o.ord < pc.ord)
                       OR EXISTS (SELECT 1 FROM @keptChoices k WHERE k.productOptionChoiceId = pc.choiceId));

                UPDATE c
                SET choiceKey = pc.choiceKey, name = pc.name, price = pc.price, description = pc.description,
                    quantity = pc.quantity, measurementId = pc.measurementId, isActive = 1, updatedAt = GETDATE()
                FROM dbo.productOptionChoices c
                JOIN @payloadChoices pc ON pc.choiceId = c.productOptionChoiceId;

                INSERT INTO @keptChoices (productOptionChoiceId)
                SELECT choiceId FROM @payloadChoices WHERE choiceId IS NOT NULL;

                INSERT INTO dbo.productOptionChoices (productOptionId, choiceKey, name, price, description, quantity, measurementId, isActive, createdAt, updatedAt)
                OUTPUT inserted.productOptionChoiceId INTO @keptChoices (productOptionChoiceId)
                SELECT @optId, choiceKey, name, price, description, quantity, measurementId, 1, GETDATE(), GETDATE()
                FROM @payloadChoices WHERE choiceId IS NULL
                ORDER BY ord;

                SET @index = @index + 1;
            END

            -- Rows left out of the payload: delete if no history uses them, else deactivate.
            -- (Add dbo.productConsumptions to these checks when phase 2 creates it.)
            DECLARE @goneChoices TABLE (id INT PRIMARY KEY);
            INSERT INTO @goneChoices (id)
            SELECT c.productOptionChoiceId
            FROM dbo.productOptionChoices c
            JOIN dbo.productOptions o ON o.productOptionId = c.productOptionId
            WHERE o.productId = @productId
              AND c.productOptionChoiceId NOT IN (SELECT productOptionChoiceId FROM @keptChoices);

            UPDATE c SET isActive = 0, updatedAt = GETDATE()
            FROM dbo.productOptionChoices c
            JOIN @goneChoices g ON g.id = c.productOptionChoiceId
            WHERE c.isActive = 1
              AND (EXISTS (SELECT 1 FROM dbo.incomeDetailOptions x WHERE x.productOptionChoiceId = g.id)
                   OR EXISTS (SELECT 1 FROM dbo.expenseDetailOptions x WHERE x.productOptionChoiceId = g.id)
                   OR EXISTS (SELECT 1 FROM dbo.orderDetails x WHERE x.productOptionChoiceId = g.id)
                   OR EXISTS (SELECT 1 FROM dbo.laundryDeviceUses x WHERE x.productOptionChoiceId = g.id));

            DELETE c
            FROM dbo.productOptionChoices c
            JOIN @goneChoices g ON g.id = c.productOptionChoiceId
            WHERE NOT EXISTS (SELECT 1 FROM dbo.incomeDetailOptions x WHERE x.productOptionChoiceId = g.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.expenseDetailOptions x WHERE x.productOptionChoiceId = g.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.orderDetails x WHERE x.productOptionChoiceId = g.id)
              AND NOT EXISTS (SELECT 1 FROM dbo.laundryDeviceUses x WHERE x.productOptionChoiceId = g.id);

            -- An option left out: kept (inactive) while history or a deactivated choice needs it.
            UPDATE o SET isActive = 0, updatedAt = GETDATE()
            FROM dbo.productOptions o
            WHERE o.productId = @productId AND o.isActive = 1
              AND o.productOptionId NOT IN (SELECT productOptionId FROM @keptOptions)
              AND (EXISTS (SELECT 1 FROM dbo.productOptionChoices c WHERE c.productOptionId = o.productOptionId)
                   OR EXISTS (SELECT 1 FROM dbo.incomeDetailOptions x WHERE x.productOptionId = o.productOptionId)
                   OR EXISTS (SELECT 1 FROM dbo.expenseDetailOptions x WHERE x.productOptionId = o.productOptionId)
                   OR EXISTS (SELECT 1 FROM dbo.orderDetails x WHERE x.productOptionId = o.productOptionId));

            DELETE o
            FROM dbo.productOptions o
            WHERE o.productId = @productId
              AND o.productOptionId NOT IN (SELECT productOptionId FROM @keptOptions)
              AND NOT EXISTS (SELECT 1 FROM dbo.productOptionChoices c WHERE c.productOptionId = o.productOptionId)
              AND NOT EXISTS (SELECT 1 FROM dbo.incomeDetailOptions x WHERE x.productOptionId = o.productOptionId)
              AND NOT EXISTS (SELECT 1 FROM dbo.expenseDetailOptions x WHERE x.productOptionId = o.productOptionId)
              AND NOT EXISTS (SELECT 1 FROM dbo.orderDetails x WHERE x.productOptionId = o.productOptionId);
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

-- 5) dbo.sp_products_by_company ----------------------------------------------------------
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
        p.stockUnit,
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
                    WHERE c.productOptionId = o.productOptionId AND c.isActive = 1
                    FOR JSON PATH
                ) AS choices
            FROM productOptions o
            WHERE o.productId = p.productId AND o.isActive = 1
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

-- 6) dbo.sp_products_one ------------------------------------------------------------------
CREATE OR ALTER PROC [dbo].[sp_products_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "products": [ { "companyId": "1", "productId": "1" } ] }'
    */

    DECLARE @productId INT;
    DECLARE @companyId INT = TRY_CAST(JSON_VALUE(@pjsonfile, '$.products[0].companyId') AS INT);

    -- Extracting ProductId safely
    SET @productId = TRY_CAST((SELECT JSON_VALUE(value, '$.productId') FROM OPENJSON(@pjsonfile, '$.products')) AS INT);

    -- A product is only returned to its own company.
    IF @companyId IS NULL
    BEGIN
        SELECT '{"error":"companyId is required"}';
        RETURN;
    END

    -- Every column the wizard edits must come back here — including the option and
    -- choice ids, which the wizard sends back so sp_products updates them in place: the next save writes
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
        ,p.[stockUnit]
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
                po.productOptionId
                ,po.optionKey
                ,po.name
                ,po.type
                ,po.isRequired
                ,(
                    SELECT
                        poc.productOptionChoiceId
                        ,poc.choiceKey
                        ,poc.name
                        ,poc.price
                        ,poc.description
                        ,poc.quantity
                        ,poc.measurementId
                        ,m.prefix AS unit
                    FROM dbo.productOptionChoices poc
                    LEFT JOIN dbo.measurements m ON m.measurementId = poc.measurementId
                    WHERE poc.productOptionId = po.productOptionId AND poc.isActive = 1
                    FOR JSON PATH
                ) AS optionChoices
            FROM dbo.productOptions po
            WHERE po.productId = p.productId AND po.isActive = 1
            FOR JSON PATH
        ) AS productOptions

    FROM
        [dbo].[products] p
    LEFT JOIN dbo.inventoryStock inv
        ON inv.companyId = p.companyId AND inv.productId = p.productId
    WHERE
        p.productId = @productId
        AND p.companyId = @companyId
    FOR JSON PATH, ROOT('products');

END
GO

-- 7) dbo.sp_products_food (live definition + isActive filter) ----------------------------
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
      @categoryId = TRY_CAST(COALESCE(JSON_VALUE(j.value, '$.productCategoryId'), JSON_VALUE(j.value, '$.categoryId')) AS INT)
    FROM OPENJSON(@pjsonfile, '$.products') AS j;
  END

  SELECT
      p.productId AS [id],
      p.name,
      p.description,
      pd.saleprice AS price,
      NULL AS [image],
      p.productCategoryId AS categoryId,
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
              WHERE c.productOptionId = o.productOptionId AND c.isActive = 1
              FOR JSON PATH
            ) AS choices
        FROM dbo.productOptions AS o
        WHERE o.productId = p.productId AND o.isActive = 1
        FOR JSON PATH
      ) AS options
  FROM dbo.products AS p
  INNER JOIN dbo.productdetails AS pd
          ON pd.productId = p.productId
  WHERE EXISTS (SELECT 1 FROM dbo.productOptions o WHERE o.productId = p.productId)
    --AND (@companyId IS NULL OR p.companyId = @companyId)
    AND (@categoryId IS NULL OR p.productCategoryId = @categoryId)
  FOR JSON PATH, ROOT('products');
END
GO

-- 8) dbo.sp_laundryDevices (live definition + isActive filter on action 7) ---------------
CREATE OR ALTER PROCEDURE [dbo].[sp_laundryDevices]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action          INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].action'))
        DECLARE @deviceId        INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].deviceId'))
        DECLARE @companyId       INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].companyId'))
        DECLARE @branchId        INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].branchId'))
        DECLARE @name            NVARCHAR(60)  = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].name')
        DECLARE @machineType     NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].machineType')
        DECLARE @productId       INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].productId'))
        DECLARE @choiceId        INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].productOptionChoiceId'))
        DECLARE @priceMXN        DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.laundryDevices[0].priceMXN'))
        DECLARE @cycleMinutes    INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].cycleMinutes'))
        DECLARE @isActive        BIT           = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].isActive'))
        DECLARE @keyHash         CHAR(64)      = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].keyHash')
        DECLARE @status          NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].status')
        DECLARE @firmwareVersion NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].firmwareVersion')
        DECLARE @ip              NVARCHAR(45)  = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].ip')
        DECLARE @rssi            INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].rssi'))

        IF @action = 1
        BEGIN
            IF @companyId IS NULL OR @name IS NULL OR @machineType IS NULL OR @keyHash IS NULL
               OR (@productId IS NULL AND @priceMXN IS NULL)
            BEGIN
                SELECT '{"error":"companyId, name, machineType y productId o priceMXN son requeridos"}' AS [jsonResult]
                RETURN
            END
            IF @productId IS NOT NULL AND NOT EXISTS
                (SELECT 1 FROM [dbo].[products] WHERE productId = @productId AND companyId = @companyId)
            BEGIN
                SELECT '{"error":"product_not_found"}' AS [jsonResult]
                RETURN
            END
            INSERT INTO [dbo].[laundryDevices] (companyId, branchId, name, machineType, productId, priceMXN, cycleMinutes, keyHash)
            VALUES (@companyId, @branchId, @name, @machineType, @productId, @priceMXN, ISNULL(@cycleMinutes, 45), @keyHash)
            SET @deviceId = SCOPE_IDENTITY()
        END
        ELSE IF @action = 2
        BEGIN
            UPDATE [dbo].[laundryDevices]
            SET name         = ISNULL(@name, name),
                branchId     = ISNULL(@branchId, branchId),
                productId    = ISNULL(@productId, productId),
                priceMXN     = ISNULL(@priceMXN, priceMXN),
                cycleMinutes = ISNULL(@cycleMinutes, cycleMinutes),
                isActive     = ISNULL(@isActive, isActive),
                updated_At   = SYSUTCDATETIME()
            WHERE deviceId = @deviceId AND companyId = @companyId
            IF @@ROWCOUNT = 0
            BEGIN
                SELECT '{"error":"device_not_found"}' AS [jsonResult]
                RETURN
            END
        END
        ELSE IF @action = 3
        BEGIN
            UPDATE [dbo].[laundryDevices]
            SET keyHash = @keyHash, updated_At = SYSUTCDATETIME()
            WHERE deviceId = @deviceId AND companyId = @companyId AND @keyHash IS NOT NULL
            IF @@ROWCOUNT = 0
            BEGIN
                SELECT '{"error":"device_not_found"}' AS [jsonResult]
                RETURN
            END
        END
        ELSE IF @action = 4
        BEGIN
            SELECT ISNULL(
                (SELECT deviceId, companyId, branchId, name, machineType, productId, priceMXN, cycleMinutes,
                        keyHash, CAST(isActive AS INT) AS isActive
                 FROM [dbo].[laundryDevices] WHERE deviceId = @deviceId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{"error":"device_not_found"}') AS [jsonResult]
            RETURN
        END
        ELSE IF @action = 5
        BEGIN
            UPDATE [dbo].[laundryDevices]
            SET lastSeenAtUtc   = SYSUTCDATETIME(),
                lastStatus      = ISNULL(@status, lastStatus),
                firmwareVersion = ISNULL(@firmwareVersion, firmwareVersion),
                lastIp          = ISNULL(@ip, lastIp),
                lastRssi        = ISNULL(@rssi, lastRssi)
            WHERE deviceId = @deviceId
        END
        ELSE IF @action = 6
        BEGIN
            DECLARE @devProductId INT, @devPrice DECIMAL(12,2), @devCompanyId INT
            SELECT @devProductId = productId, @devPrice = priceMXN, @devCompanyId = companyId
            FROM [dbo].[laundryDevices] WHERE deviceId = @deviceId

            IF @devProductId IS NULL
            BEGIN
                IF @choiceId IS NOT NULL OR @devPrice IS NULL
                    SELECT '{"error":"choice_not_for_device"}' AS [jsonResult]
                ELSE
                    SELECT (SELECT @devPrice AS priceMXN FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
                RETURN
            END

            SELECT ISNULL(
                (SELECT c.price AS priceMXN, c.productOptionChoiceId, c.name AS choiceName
                 FROM [dbo].[productOptionChoices] c
                 JOIN [dbo].[productOptions] o ON o.productOptionId = c.productOptionId
                 JOIN [dbo].[products] p ON p.productId = o.productId
                 WHERE c.productOptionChoiceId = @choiceId
                   AND o.productId = @devProductId
                   AND p.companyId = @devCompanyId
                   AND c.price > 0
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{"error":"choice_not_for_device"}') AS [jsonResult]
            RETURN
        END
        ELSE IF @action = 7
        BEGIN
            SELECT ISNULL(
                (SELECT c.productOptionChoiceId, c.name, c.price AS priceMXN, c.description
                 FROM [dbo].[laundryDevices] d
                 JOIN [dbo].[products] p ON p.productId = d.productId AND p.companyId = d.companyId
                 JOIN [dbo].[productOptions] o ON o.productId = p.productId
                 JOIN [dbo].[productOptionChoices] c ON c.productOptionId = o.productOptionId
                 WHERE d.deviceId = @deviceId AND c.price > 0 AND c.isActive = 1 AND o.isActive = 1
                 ORDER BY c.price, c.productOptionChoiceId
                 FOR JSON PATH, ROOT('cycles')),
                '{"cycles":[]}') AS [jsonResult]
            RETURN
        END
        ELSE IF @action = 8
        BEGIN
            DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].clientId'))
            SELECT ISNULL(
                (SELECT c.clientId, LTRIM(RTRIM(c.first_name)) AS firstName
                 FROM [dbo].[clients] c
                 JOIN [dbo].[laundryDevices] d ON d.companyId = c.companyId
                 WHERE d.deviceId = @deviceId AND c.clientId = @clientId AND c.isActive = 1
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{"error":"client_not_found"}') AS [jsonResult]
            RETURN
        END
        ELSE
        BEGIN
            SELECT '{"error":"action no soportada"}' AS [jsonResult]
            RETURN
        END

        SELECT ISNULL(
            (SELECT deviceId, companyId, branchId, name, machineType, productId, priceMXN, cycleMinutes,
                    CAST(isActive AS INT) AS isActive, lastStatus, firmwareVersion, lastIp, lastRssi,
                    CONVERT(NVARCHAR, lastSeenAtUtc, 127) AS lastSeenAtUtc,
                    CONVERT(NVARCHAR, SYSUTCDATETIME(), 127) AS serverTimeUtc
             FROM [dbo].[laundryDevices] WHERE deviceId = @deviceId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            '{"error":"device_not_found"}') AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- 9) Purchase trigger: quantities in the stock unit ----------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_expenseDetails_inventory
ON dbo.expenseDetails
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    -- Posts purchases to the inventory ledger. See the header of
    -- 2026-10-15c_inventory_single_source.sql for the rules.
    -- Quantities are converted to the product's stockUnit (fn_stockFactor): 1 × 8 L
    -- counted in ml posts 8000. A product whose content can't be converted (factor
    -- NULL) posts nothing — sp_products refuses that state on save.
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
        SELECT i.expenseId AS refId, i.productId, CAST(i.quantity * dbo.fn_stockFactor(i.productId) AS DECIMAL(18,3)) AS q, 1 AS needsTracking
        FROM inserted i
        WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.expenseDetailId = i.expenseDetailId)

        UNION ALL
        -- Deleted or edited line: undo only what this ledger posted for it.
        SELECT d.expenseId, d.productId, -CAST(d.quantity * dbo.fn_stockFactor(d.productId) AS DECIMAL(18,3)), 0
        FROM deleted d
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'expense' AND m.refId = d.expenseId AND m.productId = d.productId)

        UNION ALL
        -- Edited line that was posted: post its new quantity.
        SELECT i.expenseId, i.productId, CAST(i.quantity * dbo.fn_stockFactor(i.productId) AS DECIMAL(18,3)), 0
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

-- 10) Sale trigger: quantities in the stock unit -------------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_incomeDetails_inventory
ON dbo.incomeDetails
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    -- Posts sales to the inventory ledger. See the header of
    -- 2026-10-15c_inventory_single_source.sql for the rules.
    -- Quantities are converted to the product's stockUnit (fn_stockFactor): 1 × 8 L
    -- counted in ml posts 8000. A product whose content can't be converted (factor
    -- NULL) posts nothing — sp_products refuses that state on save.
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
        SELECT i.incomeId AS refId, i.productId, -CAST(i.quantity * dbo.fn_stockFactor(i.productId) AS DECIMAL(18,3)) AS q, 1 AS needsTracking
        FROM inserted i
        WHERE NOT EXISTS (SELECT 1 FROM deleted d WHERE d.incomeDetailId = i.incomeDetailId)

        UNION ALL
        -- Deleted or edited line: undo only what this ledger posted for it.
        SELECT d.incomeId, d.productId, CAST(d.quantity * dbo.fn_stockFactor(d.productId) AS DECIMAL(18,3)), 0
        FROM deleted d
        WHERE EXISTS (SELECT 1 FROM dbo.inventoryMovements m
                      WHERE m.refType = 'income' AND m.refId = d.incomeId AND m.productId = d.productId)

        UNION ALL
        -- Edited line that was posted: post its new quantity.
        SELECT i.incomeId, i.productId, -CAST(i.quantity * dbo.fn_stockFactor(i.productId) AS DECIMAL(18,3)), 0
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

-- Verify ----------------------------------------------------------------------------------
SELECT
    CASE WHEN COL_LENGTH('dbo.productOptions', 'isActive') IS NOT NULL
          AND COL_LENGTH('dbo.productOptionChoices', 'isActive') IS NOT NULL THEN 1 ELSE 0 END AS hasIsActive,
    CASE WHEN COL_LENGTH('dbo.products', 'stockUnit') IS NOT NULL THEN 1 ELSE 0 END AS hasStockUnit,
    (SELECT COUNT(*) FROM dbo.products WHERE stockUnit <> 'pz') AS productsNotPz,          -- 0 right after the run
    dbo.fn_convertQuantity(8, 'L', 'ml') AS eightLitersInMl,                                -- 8000
    CASE WHEN CHARINDEX('stableOptionIds', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products'))) > 0 THEN 1 ELSE 0 END AS spProductsUpsert,
    CASE WHEN CHARINDEX('fn_stockFactor', OBJECT_DEFINITION(OBJECT_ID('dbo.trg_expenseDetails_inventory'))) > 0
          AND CHARINDEX('fn_stockFactor', OBJECT_DEFINITION(OBJECT_ID('dbo.trg_incomeDetails_inventory'))) > 0 THEN 1 ELSE 0 END AS triggersConvert,
    CASE WHEN CHARINDEX('c.isActive = 1', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products_by_company'))) > 0
          AND CHARINDEX('poc.isActive = 1', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products_one'))) > 0
          AND CHARINDEX('c.isActive = 1', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_products_food'))) > 0
          AND CHARINDEX('c.isActive = 1', OBJECT_DEFINITION(OBJECT_ID('dbo.sp_laundryDevices'))) > 0 THEN 1 ELSE 0 END AS readersFilter;
GO
