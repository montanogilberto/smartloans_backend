-- =============================================================================
-- Inventory phases 2-3: recipes (productConsumptions) posted on every sale,
-- availability in the POS menu, Servicio Completo recipes (companyId = 1)
-- =============================================================================
-- Design: POSVending docs/inventory-portions-design.md (§4.2, §5.3, §6, §8).
-- Run manually against the live DB AFTER 2026-10-27b (stockUnit, stable choice ids).
-- Re-runnable: guarded ALTERs/data + CREATE OR ALTER.
--
-- dbo.productConsumptions and its 3 SPs were created by the posgmo-factory
-- (PRD posgmo-factory/tests/prd_productConsumption.json, 2026-10-26). Its template
-- ignored the PRD hints, so this file finishes the module:
--   1. Table: quantity DECIMAL(18,3), + measurementId (the rule's own unit: the
--      owner writes "100 ml" / "30 g" whatever the item is counted in; NULL = pieces
--      or cycles), isActive DEFAULT 1, CHECK quantity > 0, CHECK component <>
--      product, one rule per (product, choice, component, component choice).
--   2. dbo.fn_ruleQuantity(component, qty, measurementId): the rule in the
--      component's stockUnit — ml/g items convert (L↔ml, kg↔g); 'pz' items with a
--      net content take a fraction of a piece (100 ml of an 8.5 L bottle); NULL when
--      it can't be converted (no net content yet) → that rule posts nothing until
--      the content is captured, then starts on its own.
--      dbo.fn_recipeAvailable(productId, choiceId): how many can still be sold
--      = MIN(FLOOR(stock / rule qty)) over the convertible active rules whose
--      component is a tracked stock item (choice rules + product-level rules).
--      NULL = no stock rule (unlimited). Negative stock counts as 0.
--   3. sp_productConsumptions: action 1 REPLACES a product's whole recipe (the
--      wizard saves it at once) with ownership checks; 2 updates one rule; 3 deletes
--      one. Returns {"result":[...]} as ONE JSON document (execute_sp_json reads
--      column 0; the factory's plain rowset reached the client as the bare value).
--   4. sp_productConsumptions_all: companyId + optional productId, with names,
--      component stockUnit / trackInventory / stock, as JSON.
--   5. trg_incomeDetailOptions_consumption: a sold choice consumes its recipe
--      (choice qty × rule qty, already in the component's stockUnit). Movements are
--      refType 'income_option', refId = incomeDetailOptionId; deleting the row
--      (sp_income action 2) reverses EXACTLY what was posted for it, even if the
--      recipe changed since. Service components (trackInventory = 0) post nothing.
--   6. trg_incomeDetails_consumption: same for product-level rules
--      (productOptionChoiceId NULL), refType 'income_line', refId = incomeDetailId.
--   7. sp_products_by_company: each choice returns `available` and `recipe`
--      (what it includes; `pending` = stock item without a convertible size), each
--      product returns `available` (NULL = unlimited).
--      Policy: the DB never blocks a sale; the POS warns at 0.
--   8. Data (owner's table, 2026-10-27):
--      - "8L ARIEL REG" (3027) counted in ml and "1.2.3 … 10 kg" (3029) in g
--        (balance × 8000 / × 10000, 'unit_change' movement).
--      - New supplies "Perlas" and "Aroma" (Productos, tracked, stock 0, no size yet).
--      - Servicio Completo (1004) recipes (jabón líquido = Ariel, agua chico/medio/
--        alto = Lavado Basico/Medio/Carga Alta):
--          Básico      100 ml Ariel + 100 ml Suavitel + Lavado Basico     + Secado 40 Min
--          Medio       150 ml Ariel + 150 ml Suavitel + Lavado Medio      + Secado 50 Min
--          Carga Alta  200 ml Ariel + 200 ml Suavitel + Lavado Carga Alta + Secado 60 Min
--          Colchas     200 ml Ariel + 200 ml Suavitel + 100 g 1.2.3 polvo + 30 g Perlas
--                      + 10 ml Aroma + Lavado Colcha Grandes + Secado Colchas Grandes (65 min)
--      WAITING FOR A SIZE (rules exist, post nothing yet): Suavitel (3023), Perlas,
--      Aroma — capture the net content in the product wizard.
-- Not back-filled: sales before this run consumed nothing (opening count = day 0).
-- ROLLBACK: 2026-10-27c_inventory_phase2_recipes_ROLLBACK.sql (run it BEFORE the
--           2026-10-27b rollback).
-- =============================================================================

SET NOCOUNT ON;
IF OBJECT_ID('dbo.productConsumptions', 'U') IS NULL
    THROW 50200, 'dbo.productConsumptions does not exist: run the factory DDL first.', 1;
IF COL_LENGTH('dbo.products', 'stockUnit') IS NULL
    THROW 50201, 'Run 2026-10-27b (products.stockUnit) first.', 1;
GO

-- 1) Table hardening -----------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id
           WHERE c.object_id = OBJECT_ID('dbo.productConsumptions') AND c.name = 'quantity' AND c.scale <> 3)
    ALTER TABLE dbo.productConsumptions ALTER COLUMN quantity DECIMAL(18,3) NOT NULL;
GO
IF COL_LENGTH('dbo.productConsumptions', 'measurementId') IS NULL
    ALTER TABLE dbo.productConsumptions ADD measurementId INT NULL
        CONSTRAINT FK_productConsumptions_measurements_measurementId REFERENCES dbo.measurements (measurementId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_productConsumptions_isActive')
    ALTER TABLE dbo.productConsumptions ADD CONSTRAINT DF_productConsumptions_isActive DEFAULT (1) FOR isActive;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_productConsumptions_quantity')
    ALTER TABLE dbo.productConsumptions ADD CONSTRAINT CK_productConsumptions_quantity CHECK (quantity > 0);
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_productConsumptions_notSelf')
    ALTER TABLE dbo.productConsumptions ADD CONSTRAINT CK_productConsumptions_notSelf CHECK (componentProductId <> productId);
-- A unique index treats NULLs as equal: one product-level rule per component.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_productConsumptions_rule')
    CREATE UNIQUE INDEX UX_productConsumptions_rule ON dbo.productConsumptions
        (productId, productOptionChoiceId, componentProductId, componentProductOptionChoiceId);
GO

-- 2) Rule quantity in stock units + availability ----------------------------------------
CREATE OR ALTER FUNCTION dbo.fn_ruleQuantity (@componentId INT, @qty DECIMAL(18,6), @measurementId INT)
RETURNS DECIMAL(18,6)
AS
BEGIN
    -- A rule ("100 ml") in the component's stockUnit. NULL = can't be converted yet.
    DECLARE @u VARCHAR(10), @stockUnit VARCHAR(10), @content DECIMAL(18,6), @contentUnit VARCHAR(10);
    SELECT @u = prefix FROM dbo.measurements WHERE measurementId = @measurementId;
    SELECT @stockUnit = stockUnit, @content = netContent, @contentUnit = unitOfMeasure
    FROM dbo.products WHERE productId = @componentId;
    IF @qty IS NULL OR @stockUnit IS NULL RETURN NULL;
    IF @u IS NULL OR LOWER(@u) = LOWER(@stockUnit) RETURN @qty;      -- pieces / cycles / same unit
    IF @stockUnit IN ('ml', 'g') RETURN dbo.fn_convertQuantity(@qty, @u, @stockUnit);
    IF @stockUnit = 'pz' AND @content > 0                             -- fraction of one piece
        RETURN dbo.fn_convertQuantity(@qty, @u, @contentUnit) / @content;
    RETURN NULL;
END
GO

CREATE OR ALTER FUNCTION dbo.fn_recipeAvailable (@productId INT, @choiceId INT)
RETURNS INT
AS
BEGIN
    -- How many of this product (or of one of its choices) the stock still covers.
    -- @choiceId NULL → only product-level rules. NULL result = no stock rule.
    DECLARE @a INT;
    SELECT @a = MIN(CAST(FLOOR(ISNULL(s.stockQuantity, 0) / q.perSale) AS INT))
    FROM dbo.productConsumptions r
    JOIN dbo.products cp ON cp.productId = r.componentProductId AND cp.trackInventory = 1
    CROSS APPLY (SELECT dbo.fn_ruleQuantity(r.componentProductId, r.quantity, r.measurementId) AS perSale) q
    LEFT JOIN dbo.inventoryStock s ON s.companyId = cp.companyId AND s.productId = cp.productId
    WHERE r.productId = @productId AND r.isActive = 1 AND q.perSale > 0
      AND (r.productOptionChoiceId IS NULL OR r.productOptionChoiceId = @choiceId);
    RETURN CASE WHEN @a < 0 THEN 0 ELSE @a END;
END
GO

-- 3) sp_productConsumptions ---------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_productConsumptions] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    /*
    -- 1: replace the whole recipe of a product (rules: [] clears it)
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "productConsumptions": [ { "action": 1, "companyId": 1, "productId": 1004,
        "rules": [ { "productOptionChoiceId": 2007, "componentProductId": 3027, "componentProductOptionChoiceId": null, "quantity": 100, "unit": "ml", "isActive": 1 } ] } ] }'
    -- 2: update one rule / 3: delete one rule
    DECLARE @pjsonfile VARCHAR(MAX) = '{ "productConsumptions": [ { "action": 2, "companyId": 1, "productConsumptionId": 5, "quantity": 120, "isActive": 1 } ] }'
    */

    DECLARE @Outputmessage NVARCHAR(MAX) = '{ "result": [ { "value": "", "msg": "", "error": "" } ] }';
    DECLARE @action INT, @companyId INT, @productId INT, @ruleId INT,
            @quantity DECIMAL(18,3), @isActive BIT, @rulesJson NVARCHAR(MAX);

    SELECT TOP (1)
        @action    = TRY_CONVERT(INT, JSON_VALUE(value, '$.action')),
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @productId = TRY_CONVERT(INT, JSON_VALUE(value, '$.productId')),
        @ruleId    = TRY_CONVERT(INT, JSON_VALUE(value, '$.productConsumptionId')),
        @quantity  = TRY_CONVERT(DECIMAL(18,3), JSON_VALUE(value, '$.quantity')),
        @isActive  = TRY_CONVERT(BIT, JSON_VALUE(value, '$.isActive')),
        @rulesJson = JSON_QUERY(value, '$.rules')
    FROM OPENJSON(@pjsonfile, '$.productConsumptions');

    -- Roll back only what this SP opened (validation errors never touch a caller's transaction).
    DECLARE @startTranCount INT = @@TRANCOUNT;
    DECLARE @rules TABLE (
        productOptionChoiceId INT NULL, componentProductId INT NULL,
        componentProductOptionChoiceId INT NULL, quantity DECIMAL(18,3) NULL, unit VARCHAR(10) NULL,
        measurementId INT NULL, isActive BIT NULL);

    BEGIN TRY
        IF @companyId IS NULL
            THROW 50210, 'companyId es requerido.', 1;

        IF @action = 1
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.products WHERE productId = @productId AND companyId = @companyId)
                THROW 50211, 'El producto no existe en esta empresa.', 1;

            INSERT INTO @rules
            SELECT NULLIF(j.productOptionChoiceId, 0), j.componentProductId,
                   NULLIF(j.componentProductOptionChoiceId, 0), j.quantity, NULLIF(LTRIM(RTRIM(j.unit)), ''),
                   COALESCE(NULLIF(j.measurementId, 0), m.measurementId), ISNULL(j.isActive, 1)
            FROM OPENJSON(ISNULL(@rulesJson, '[]'))
            WITH (productOptionChoiceId INT '$.productOptionChoiceId',
                  componentProductId INT '$.componentProductId',
                  componentProductOptionChoiceId INT '$.componentProductOptionChoiceId',
                  quantity DECIMAL(18,3) '$.quantity',
                  unit VARCHAR(10) '$.unit',                 -- 'ml' | 'L' | 'g' | 'kg' | 'pz' (or measurementId)
                  measurementId INT '$.measurementId',
                  isActive BIT '$.isActive') j
            LEFT JOIN dbo.measurements m ON m.prefix = NULLIF(LTRIM(RTRIM(j.unit)), '');

            IF EXISTS (SELECT 1 FROM @rules WHERE unit IS NOT NULL AND measurementId IS NULL)
                THROW 50219, 'Unidad no reconocida (usa ml, L, g, kg o pz).', 1;

            IF EXISTS (SELECT 1 FROM @rules WHERE ISNULL(quantity, 0) <= 0)
                THROW 50212, 'Cada consumo necesita una cantidad mayor a 0.', 1;
            IF EXISTS (SELECT 1 FROM @rules r WHERE r.componentProductId = @productId
                       OR NOT EXISTS (SELECT 1 FROM dbo.products cp WHERE cp.productId = r.componentProductId AND cp.companyId = @companyId))
                THROW 50213, 'Un componente no existe en esta empresa (o es el mismo producto).', 1;
            IF EXISTS (SELECT 1 FROM @rules r WHERE r.productOptionChoiceId IS NOT NULL
                       AND NOT EXISTS (SELECT 1 FROM dbo.productOptionChoices ch
                                       JOIN dbo.productOptions o ON o.productOptionId = ch.productOptionId
                                       WHERE ch.productOptionChoiceId = r.productOptionChoiceId AND o.productId = @productId))
                THROW 50214, 'Una opción no pertenece a este producto.', 1;
            IF EXISTS (SELECT 1 FROM @rules r WHERE r.componentProductOptionChoiceId IS NOT NULL
                       AND NOT EXISTS (SELECT 1 FROM dbo.productOptionChoices ch
                                       JOIN dbo.productOptions o ON o.productOptionId = ch.productOptionId
                                       WHERE ch.productOptionChoiceId = r.componentProductOptionChoiceId AND o.productId = r.componentProductId))
                THROW 50215, 'La opción del componente no pertenece a ese componente.', 1;
            IF EXISTS (SELECT 1 FROM @rules
                       GROUP BY productOptionChoiceId, componentProductId, componentProductOptionChoiceId HAVING COUNT(*) > 1)
                THROW 50216, 'Hay un consumo repetido.', 1;

            BEGIN TRANSACTION;
            -- Sales keep their ledger (movements point at the sold row, not the rule).
            DELETE FROM dbo.productConsumptions WHERE productId = @productId AND companyId = @companyId;
            INSERT INTO dbo.productConsumptions
                (companyId, productId, productOptionChoiceId, componentProductId, componentProductOptionChoiceId, quantity, measurementId, isActive, created_At)
            SELECT @companyId, @productId, productOptionChoiceId, componentProductId, componentProductOptionChoiceId, quantity, measurementId, isActive, GETDATE()
            FROM @rules;
            COMMIT TRANSACTION;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST((SELECT COUNT(*) FROM @rules) AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Saved Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            IF @quantity IS NOT NULL AND @quantity <= 0
                THROW 50212, 'Cada consumo necesita una cantidad mayor a 0.', 1;
            UPDATE dbo.productConsumptions
            SET quantity = ISNULL(@quantity, quantity), isActive = ISNULL(@isActive, isActive), updated_at = GETDATE()
            WHERE productConsumptionId = @ruleId AND companyId = @companyId;
            IF @@ROWCOUNT = 0 THROW 50217, 'El consumo no existe.', 1;
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@ruleId AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            DELETE FROM dbo.productConsumptions WHERE productConsumptionId = @ruleId AND companyId = @companyId;
            IF @@ROWCOUNT = 0 THROW 50217, 'El consumo no existe.', 1;
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@ruleId AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
            THROW 50218, 'Invalid action (1 replace recipe, 2 update, 3 delete)', 1;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > @startTranCount ROLLBACK TRANSACTION;
        SET @Outputmessage = JSON_MODIFY(JSON_MODIFY(@Outputmessage, '$.result[0].error', '1'), '$.result[0].msg', ERROR_MESSAGE());
    END CATCH;

    SELECT JSON_VALUE(value, '$.value') AS [value], JSON_VALUE(value, '$.msg') AS [msg], JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result')
    FOR JSON PATH, ROOT('result'), INCLUDE_NULL_VALUES;
END
GO

-- 4) sp_productConsumptions_all ----------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[sp_productConsumptions_all] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    -- DECLARE @pjsonfile VARCHAR(MAX) = '{ "productConsumptions": [ { "companyId": 1, "productId": 1004 } ] }'
    DECLARE @companyId INT, @productId INT;
    SELECT TOP (1)
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @productId = NULLIF(TRY_CONVERT(INT, JSON_VALUE(value, '$.productId')), 0)
    FROM OPENJSON(@pjsonfile, '$.productConsumptions');

    SELECT
        r.productConsumptionId,
        r.productId,
        p.name AS productName,
        r.productOptionChoiceId,
        ch.name AS choiceName,
        r.componentProductId,
        cp.name AS componentName,
        cp.stockUnit AS componentStockUnit,
        CAST(cp.trackInventory AS BIT) AS componentTrackInventory,
        CASE WHEN cp.trackInventory = 1 THEN ISNULL(s.stockQuantity, 0) END AS componentStock,
        r.componentProductOptionChoiceId,
        cch.name AS componentChoiceName,
        r.quantity,
        r.measurementId,
        mu.prefix AS unit,
        -- The rule in the component's stockUnit; NULL on a stock item = waiting for its size.
        CASE WHEN cp.trackInventory = 1 THEN CAST(dbo.fn_ruleQuantity(r.componentProductId, r.quantity, r.measurementId) AS DECIMAL(18,6)) END AS stockPerSale,
        r.isActive
    FROM dbo.productConsumptions r
    LEFT JOIN dbo.measurements mu ON mu.measurementId = r.measurementId
    JOIN dbo.products p ON p.productId = r.productId
    JOIN dbo.products cp ON cp.productId = r.componentProductId
    LEFT JOIN dbo.productOptionChoices ch ON ch.productOptionChoiceId = r.productOptionChoiceId
    LEFT JOIN dbo.productOptionChoices cch ON cch.productOptionChoiceId = r.componentProductOptionChoiceId
    LEFT JOIN dbo.inventoryStock s ON s.companyId = cp.companyId AND s.productId = cp.productId
    WHERE r.companyId = @companyId AND (@productId IS NULL OR r.productId = @productId)
    ORDER BY p.name, r.productOptionChoiceId, cp.trackInventory DESC, cp.name
    FOR JSON PATH, ROOT('productConsumptions'), INCLUDE_NULL_VALUES;
END
GO

-- 5) Sold choices consume their recipe ------------------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_incomeDetailOptions_consumption
ON dbo.incomeDetailOptions
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    -- See the header of 2026-10-27c_inventory_phase2_recipes.sql.
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @m TABLE (companyId INT NOT NULL, productId INT NOT NULL, refId INT NOT NULL,
                      quantityDelta DECIMAL(18,3) NOT NULL, userId INT NULL, notes NVARCHAR(300) NULL);

    -- Removed / edited rows: undo exactly what the ledger posted for them.
    INSERT INTO @m (companyId, productId, refId, quantityDelta, userId, notes)
    SELECT mv.companyId, mv.productId, mv.refId, -SUM(mv.quantityDelta), MAX(mv.userId), NULL
    FROM dbo.inventoryMovements mv
    JOIN deleted d ON mv.refType = 'income_option' AND mv.refId = d.incomeDetailOptionId
    GROUP BY mv.companyId, mv.productId, mv.refId
    HAVING SUM(mv.quantityDelta) <> 0;

    -- New / edited rows: post the current recipe of the sold choice.
    INSERT INTO @m (companyId, productId, refId, quantityDelta, userId, notes)
    SELECT COALESCE(h.companyId, p.companyId), r.componentProductId, i.incomeDetailOptionId,
           -SUM(CAST(i.quantity * q.perSale AS DECIMAL(18,3))), MAX(h.userId),
           MAX(CONCAT(N'Receta: ', p.name, N' › ', ch.name))
    FROM inserted i
    JOIN dbo.incomeDetails d ON d.incomeDetailId = i.incomeDetailId
    JOIN dbo.products p ON p.productId = d.productId
    JOIN dbo.productOptionChoices ch ON ch.productOptionChoiceId = i.productOptionChoiceId
    LEFT JOIN dbo.income h ON h.incomeId = d.incomeId
    JOIN dbo.productConsumptions r ON r.productId = d.productId AND r.productOptionChoiceId = i.productOptionChoiceId AND r.isActive = 1
    JOIN dbo.products cp ON cp.productId = r.componentProductId AND cp.trackInventory = 1
    CROSS APPLY (SELECT dbo.fn_ruleQuantity(r.componentProductId, r.quantity, r.measurementId) AS perSale) q
    WHERE q.perSale IS NOT NULL
    GROUP BY COALESCE(h.companyId, p.companyId), r.componentProductId, i.incomeDetailOptionId
    HAVING SUM(CAST(i.quantity * q.perSale AS DECIMAL(18,3))) <> 0;

    IF NOT EXISTS (SELECT 1 FROM @m) RETURN;

    INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
    SELECT companyId, productId, quantityDelta,
           CASE WHEN quantityDelta < 0 THEN 'sale' ELSE 'sale_reversal' END,
           notes, 'income_option', refId, userId
    FROM @m;

    MERGE dbo.inventoryStock WITH (HOLDLOCK) AS t
    USING (SELECT companyId, productId, SUM(quantityDelta) AS delta FROM @m GROUP BY companyId, productId) AS s
       ON t.companyId = s.companyId AND t.productId = s.productId
    WHEN MATCHED THEN
        UPDATE SET stockQuantity = t.stockQuantity + s.delta, updatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (companyId, productId, stockQuantity) VALUES (s.companyId, s.productId, s.delta);
END
GO

-- 6) Product-level rules (every sale of the product) ------------------------------------
CREATE OR ALTER TRIGGER dbo.trg_incomeDetails_consumption
ON dbo.incomeDetails
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    -- See the header of 2026-10-27c_inventory_phase2_recipes.sql. The line's own
    -- product is posted by trg_incomeDetails_inventory; this posts its recipe.
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM inserted) AND NOT EXISTS (SELECT 1 FROM deleted) RETURN;

    DECLARE @m TABLE (companyId INT NOT NULL, productId INT NOT NULL, refId INT NOT NULL,
                      quantityDelta DECIMAL(18,3) NOT NULL, userId INT NULL, notes NVARCHAR(300) NULL);

    INSERT INTO @m (companyId, productId, refId, quantityDelta, userId, notes)
    SELECT mv.companyId, mv.productId, mv.refId, -SUM(mv.quantityDelta), MAX(mv.userId), NULL
    FROM dbo.inventoryMovements mv
    JOIN deleted d ON mv.refType = 'income_line' AND mv.refId = d.incomeDetailId
    GROUP BY mv.companyId, mv.productId, mv.refId
    HAVING SUM(mv.quantityDelta) <> 0;

    INSERT INTO @m (companyId, productId, refId, quantityDelta, userId, notes)
    SELECT COALESCE(h.companyId, p.companyId), r.componentProductId, i.incomeDetailId,
           -SUM(CAST(i.quantity * q.perSale AS DECIMAL(18,3))), MAX(h.userId),
           MAX(CONCAT(N'Receta: ', p.name))
    FROM inserted i
    JOIN dbo.products p ON p.productId = i.productId
    LEFT JOIN dbo.income h ON h.incomeId = i.incomeId
    JOIN dbo.productConsumptions r ON r.productId = i.productId AND r.productOptionChoiceId IS NULL AND r.isActive = 1
    JOIN dbo.products cp ON cp.productId = r.componentProductId AND cp.trackInventory = 1
    CROSS APPLY (SELECT dbo.fn_ruleQuantity(r.componentProductId, r.quantity, r.measurementId) AS perSale) q
    WHERE q.perSale IS NOT NULL
    GROUP BY COALESCE(h.companyId, p.companyId), r.componentProductId, i.incomeDetailId
    HAVING SUM(CAST(i.quantity * q.perSale AS DECIMAL(18,3))) <> 0;

    IF NOT EXISTS (SELECT 1 FROM @m) RETURN;

    INSERT INTO dbo.inventoryMovements (companyId, productId, quantityDelta, reason, notes, refType, refId, userId)
    SELECT companyId, productId, quantityDelta,
           CASE WHEN quantityDelta < 0 THEN 'sale' ELSE 'sale_reversal' END,
           notes, 'income_line', refId, userId
    FROM @m;

    MERGE dbo.inventoryStock WITH (HOLDLOCK) AS t
    USING (SELECT companyId, productId, SUM(quantityDelta) AS delta FROM @m GROUP BY companyId, productId) AS s
       ON t.companyId = s.companyId AND t.productId = s.productId
    WHEN MATCHED THEN
        UPDATE SET stockQuantity = t.stockQuantity + s.delta, updatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (companyId, productId, stockQuantity) VALUES (s.companyId, s.productId, s.delta);
END
GO

-- 7) sp_products_by_company: availability + recipe per choice ------------------------------
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
        -- How many can still be sold by recipe (phase 3). NULL = no stock rule.
        av.available,
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
                        m.prefix AS unit,          -- e.g. 'L'
                        dbo.fn_recipeAvailable(p.productId, c.productOptionChoiceId) AS available,
                        (
                            -- What this choice includes: stock it consumes + services.
                            SELECT r.componentProductId, cp.name AS componentName,
                                   cch.name AS componentChoiceName, r.quantity,
                                   mu.prefix AS unit, CAST(cp.trackInventory AS BIT) AS isStock,
                                   -- stock item whose size isn't captured yet: listed, not discounted
                                   CAST(CASE WHEN cp.trackInventory = 1
                                              AND dbo.fn_ruleQuantity(r.componentProductId, r.quantity, r.measurementId) IS NULL
                                             THEN 1 ELSE 0 END AS BIT) AS pending
                            FROM dbo.productConsumptions r
                            JOIN dbo.products cp ON cp.productId = r.componentProductId
                            LEFT JOIN dbo.measurements mu ON mu.measurementId = r.measurementId
                            LEFT JOIN dbo.productOptionChoices cch ON cch.productOptionChoiceId = r.componentProductOptionChoiceId
                            WHERE r.productId = p.productId AND r.isActive = 1
                              AND (r.productOptionChoiceId = c.productOptionChoiceId OR r.productOptionChoiceId IS NULL)
                            ORDER BY cp.trackInventory DESC, cp.name
                            FOR JSON PATH
                        ) AS recipe
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
    OUTER APPLY (
        -- Product card: the best choice (a choice with no stock rule = unlimited).
        SELECT CASE WHEN COUNT(*) = 0 THEN dbo.fn_recipeAvailable(p.productId, NULL)
                    WHEN SUM(CASE WHEN x.a IS NULL THEN 1 ELSE 0 END) > 0 THEN NULL
                    ELSE MAX(x.a) END AS available
        FROM (
            SELECT dbo.fn_recipeAvailable(p.productId, c2.productOptionChoiceId) AS a
            FROM dbo.productOptionChoices c2
            JOIN dbo.productOptions o2 ON o2.productOptionId = c2.productOptionId
            WHERE o2.productId = p.productId AND o2.isActive = 1 AND c2.isActive = 1
        ) x
    ) av
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

-- 8a) Data: liquid soap in ml, powder soap in g -------------------------------------------
DECLARE @u TABLE (productId INT, unit VARCHAR(10));
INSERT INTO @u VALUES (3027, 'ml'), (3029, 'g');
DECLARE @pid INT, @unit VARCHAR(10), @bal DECIMAL(18,3), @delta DECIMAL(18,3), @note NVARCHAR(300);
DECLARE cu CURSOR LOCAL FAST_FORWARD FOR SELECT productId, unit FROM @u;
OPEN cu;
FETCH NEXT FROM cu INTO @pid, @unit;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF EXISTS (SELECT 1 FROM dbo.products WHERE productId = @pid AND companyId = 1 AND stockUnit = 'pz'
               AND dbo.fn_convertQuantity(netContent, unitOfMeasure, @unit) IS NOT NULL)
    BEGIN
        BEGIN TRANSACTION;
        SELECT @bal = stockQuantity FROM dbo.inventoryStock WITH (UPDLOCK, HOLDLOCK) WHERE companyId = 1 AND productId = @pid;
        UPDATE dbo.products SET stockUnit = @unit, updatedAt = GETDATE() WHERE productId = @pid;
        IF ISNULL(@bal, 0) <> 0
        BEGIN
            SET @delta = ROUND(@bal * dbo.fn_stockFactor(@pid), 3) - @bal;
            SET @note = CONCAT(N'Unidad de inventario: pz → ', @unit);
            EXEC dbo.sp_inventory_post @companyId = 1, @productId = @pid, @quantityDelta = @delta,
                 @reason = 'unit_change', @refType = 'product_save', @refId = @pid, @userId = NULL, @notes = @note;
        END
        COMMIT TRANSACTION;
        PRINT CONCAT(@pid, ' now counted in ', @unit);
    END
    FETCH NEXT FROM cu INTO @pid, @unit;
END
CLOSE cu; DEALLOCATE cu;
GO

-- 8b) Data: new supplies Perlas and Aroma (through sp_products, stock 0) -------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.products WHERE companyId = 1 AND name = N'Perlas')
    EXEC dbo.sp_products @pjsonfile = N'{"products":[{"action":1,"companyId":1,"name":"Perlas","description":"Perlas de olor para lavado (receta Servicio Completo)","categoryId":1004,"isSupply":1,"trackInventory":1,"isActive":1,"stockUnit":"pz"}]}';
IF NOT EXISTS (SELECT 1 FROM dbo.products WHERE companyId = 1 AND name = N'Aroma')
    EXEC dbo.sp_products @pjsonfile = N'{"products":[{"action":1,"companyId":1,"name":"Aroma","description":"Aroma para lavado (receta Servicio Completo)","categoryId":1004,"isSupply":1,"trackInventory":1,"isActive":1,"stockUnit":"pz"}]}';
GO

-- 8c) Data: Servicio Completo recipes (only if it has none) -----------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.productConsumptions WHERE productId = 1004)
BEGIN
    DECLARE @perlas INT = (SELECT productId FROM dbo.products WHERE companyId = 1 AND name = N'Perlas');
    DECLARE @aroma  INT = (SELECT productId FROM dbo.products WHERE companyId = 1 AND name = N'Aroma');
    DECLARE @r TABLE (choiceId INT, componentId INT, componentChoiceId INT NULL, quantity DECIMAL(18,3), unit VARCHAR(10) NULL);
    INSERT INTO @r VALUES
        -- Básico: agua chico
        (2007, 3027, NULL, 100, 'ml'), (2007, 3023, NULL, 100, 'ml'), (2007, 1002, 1004, 1, NULL), (2007, 1003, 1008, 1, NULL),
        -- Medio: agua medio
        (2008, 3027, NULL, 150, 'ml'), (2008, 3023, NULL, 150, 'ml'), (2008, 1002, 1005, 1, NULL), (2008, 1003, 1009, 1, NULL),
        -- Carga Alta: agua alto
        (2009, 3027, NULL, 200, 'ml'), (2009, 3023, NULL, 200, 'ml'), (2009, 1002, 1006, 1, NULL), (2009, 1003, 1010, 1, NULL),
        -- Colchas Grandes: agua alto, secado 65 min
        (2010, 3027, NULL, 200, 'ml'), (2010, 3023, NULL, 200, 'ml'), (2010, 3029, NULL, 100, 'g'),
        (2010, @perlas, NULL, 30, 'g'), (2010, @aroma, NULL, 10, 'ml'),
        (2010, 1002, 1007, 1, NULL), (2010, 1003, 1011, 1, NULL);

    DECLARE @rules NVARCHAR(MAX) = (
        SELECT choiceId AS productOptionChoiceId, componentId AS componentProductId,
               componentChoiceId AS componentProductOptionChoiceId, quantity, unit, 1 AS isActive
        FROM @r FOR JSON PATH, INCLUDE_NULL_VALUES);
    DECLARE @payload VARCHAR(MAX) = CONCAT('{"productConsumptions":[{"action":1,"companyId":1,"productId":1004,"rules":', @rules, '}]}');
    -- Through the SP, so its ownership checks validate the seed.
    EXEC dbo.sp_productConsumptions @pjsonfile = @payload;
END
GO

-- Verify ---------------------------------------------------------------------------------------
SELECT ch.name AS ciclo, cp.name AS componente, cch.name AS opcion, r.quantity, mu.prefix AS unidad,
       cp.stockUnit, dbo.fn_ruleQuantity(r.componentProductId, r.quantity, r.measurementId) AS porVenta,
       dbo.fn_recipeAvailable(1004, r.productOptionChoiceId) AS disponibles
FROM dbo.productConsumptions r
LEFT JOIN dbo.measurements mu ON mu.measurementId = r.measurementId
JOIN dbo.productOptionChoices ch ON ch.productOptionChoiceId = r.productOptionChoiceId
JOIN dbo.products cp ON cp.productId = r.componentProductId
LEFT JOIN dbo.productOptionChoices cch ON cch.productOptionChoiceId = r.componentProductOptionChoiceId
WHERE r.productId = 1004
ORDER BY r.productOptionChoiceId, cp.trackInventory DESC;
