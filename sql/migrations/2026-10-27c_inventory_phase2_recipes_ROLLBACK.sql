-- =============================================================================
-- ROLLBACK of 2026-10-27c_inventory_phase2_recipes.sql
-- =============================================================================
-- Run BEFORE the 2026-10-27b rollback. Restores the factory's original
-- sp_productConsumptions / _all, phase 1's sp_products_by_company, drops the recipe
-- triggers, fn_recipeAvailable / fn_ruleQuantity, the measurementId column and the
-- constraints this file added, and counts 8L ARIEL REG (3027) and 1.2.3 polvo (3029)
-- in pz again (balance ÷ factor, 'unit_change' movement).
-- Kept: dbo.productConsumptions and its rows (factory table; delete rows by hand if
-- wanted), quantity stays DECIMAL(18,3), the "Perlas" / "Aroma" supplies (deactivate
-- them in /products-management if unwanted), and every movement already posted by
-- sales (the ledger is history; recount with an adjustment if needed).
-- =============================================================================
SET NOCOUNT ON;
GO
DROP TRIGGER IF EXISTS dbo.trg_incomeDetailOptions_consumption;
DROP TRIGGER IF EXISTS dbo.trg_incomeDetails_consumption;
GO
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_productConsumptions_rule')
    DROP INDEX UX_productConsumptions_rule ON dbo.productConsumptions;
ALTER TABLE dbo.productConsumptions DROP CONSTRAINT IF EXISTS CK_productConsumptions_quantity;
ALTER TABLE dbo.productConsumptions DROP CONSTRAINT IF EXISTS CK_productConsumptions_notSelf;
ALTER TABLE dbo.productConsumptions DROP CONSTRAINT IF EXISTS DF_productConsumptions_isActive;
GO
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

DROP FUNCTION IF EXISTS dbo.fn_recipeAvailable;
GO
DROP FUNCTION IF EXISTS dbo.fn_ruleQuantity;
GO
ALTER TABLE dbo.productConsumptions DROP CONSTRAINT IF EXISTS FK_productConsumptions_measurements_measurementId;
IF COL_LENGTH('dbo.productConsumptions', 'measurementId') IS NOT NULL
    ALTER TABLE dbo.productConsumptions DROP COLUMN measurementId;
GO
CREATE OR ALTER PROCEDURE [dbo].[sp_productConsumptions] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Outputmessage NVARCHAR(MAX) = '{
  "result": [
    { "value": "", "msg": "", "error": "" }
  ]
}';

    DECLARE @action INT;
    SET @action = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.productConsumptions')
    );

    DECLARE @payload TABLE (
        [productConsumptionId] INT NULL,
        [companyId] INT NULL,
        [productId] INT NULL,
        [productOptionChoiceId] INT NULL,
        [componentProductId] INT NULL,
        [componentProductOptionChoiceId] INT NULL,
        [quantity] DECIMAL(10,2) NULL,
        [isActive] BIT NULL
    );

    BEGIN TRY
        INSERT INTO @payload ([productConsumptionId], [companyId], [productId], [productOptionChoiceId], [componentProductId], [componentProductOptionChoiceId], [quantity], [isActive])
        SELECT [productConsumptionId], [companyId], [productId], [productOptionChoiceId], [componentProductId], [componentProductOptionChoiceId], [quantity], [isActive]
        FROM OPENJSON(@pjsonfile, '$.productConsumptions')
        WITH (
        [productConsumptionId] INT '$.productConsumptionId',
        [companyId] INT '$.companyId',
        [productId] INT '$.productId',
        [productOptionChoiceId] INT '$.productOptionChoiceId',
        [componentProductId] INT '$.componentProductId',
        [componentProductOptionChoiceId] INT '$.componentProductOptionChoiceId',
        [quantity] DECIMAL(10,2) '$.quantity',
        [isActive] BIT '$.isActive'
        );

        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            INSERT INTO [dbo].[productConsumptions] ([companyId], [productId], [productOptionChoiceId], [componentProductId], [componentProductOptionChoiceId], [quantity], [isActive], [created_At])
            SELECT p.[companyId], p.[productId], p.[productOptionChoiceId], p.[componentProductId], p.[componentProductOptionChoiceId], p.[quantity], p.[isActive], GETDATE()
            FROM @payload AS p;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(SCOPE_IDENTITY() AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            UPDATE t
            SET
                t.[productId] = ISNULL(p.[productId], t.[productId]),
                t.[productOptionChoiceId] = p.[productOptionChoiceId],
                t.[componentProductId] = ISNULL(p.[componentProductId], t.[componentProductId]),
                t.[componentProductOptionChoiceId] = p.[componentProductOptionChoiceId],
                t.[quantity] = ISNULL(p.[quantity], t.[quantity]),
                t.[isActive] = ISNULL(p.[isActive], t.[isActive]),
                t.[updated_at] = GETDATE()
            FROM [dbo].[productConsumptions] AS t
            INNER JOIN @payload AS p ON t.[productConsumptionId] = p.[productConsumptionId] AND t.[companyId] = p.[companyId];

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            DELETE t
            FROM [dbo].[productConsumptions] AS t
            INNER JOIN @payload AS p ON t.[productConsumptionId] = p.[productConsumptionId] AND t.[companyId] = p.[companyId];

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid action');
            ROLLBACK TRANSACTION;
            GOTO Finish;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
    END CATCH

Finish:
    SELECT
        JSON_VALUE(value, '$.value') AS value,
        JSON_VALUE(value, '$.msg')   AS msg,
        JSON_VALUE(value, '$.error') AS error
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_productConsumptions_all] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @companyId INT;
    SET @companyId = TRY_CONVERT(INT,
        (SELECT TOP 1 JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.productConsumptions'))
    );

    SELECT
        [productConsumptionId],
        [companyId],
        [productId],
        ISNULL([productOptionChoiceId], 0) AS [productOptionChoiceId],
        [componentProductId],
        ISNULL([componentProductOptionChoiceId], 0) AS [componentProductOptionChoiceId],
        [quantity],
        [isActive],
        [created_At],
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM [dbo].[productConsumptions]
    WHERE [companyId] = @companyId
    FOR JSON AUTO, ROOT('productConsumptions');
END
GO

DECLARE @pid INT, @bal DECIMAL(18,3), @f DECIMAL(18,6), @delta DECIMAL(18,3), @note NVARCHAR(300);
DECLARE cu CURSOR LOCAL FAST_FORWARD FOR
    SELECT productId FROM dbo.products WHERE productId IN (3027, 3029) AND stockUnit IN ('ml', 'g');
OPEN cu;
FETCH NEXT FROM cu INTO @pid;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRANSACTION;
    SET @f = dbo.fn_stockFactor(@pid);
    SET @note = CONCAT(N'Unidad de inventario: ', (SELECT stockUnit FROM dbo.products WHERE productId = @pid), N' → pz');
    SELECT @bal = stockQuantity FROM dbo.inventoryStock WITH (UPDLOCK, HOLDLOCK) WHERE companyId = 1 AND productId = @pid;
    UPDATE dbo.products SET stockUnit = 'pz', updatedAt = GETDATE() WHERE productId = @pid;
    IF ISNULL(@bal, 0) <> 0 AND @f IS NOT NULL
    BEGIN
        SET @delta = ROUND(@bal / @f, 3) - @bal;
        EXEC dbo.sp_inventory_post @companyId = 1, @productId = @pid, @quantityDelta = @delta,
             @reason = 'unit_change', @refType = 'product_save', @refId = @pid, @userId = NULL, @notes = @note;
    END
    COMMIT TRANSACTION;
    FETCH NEXT FROM cu INTO @pid;
END
CLOSE cu; DEALLOCATE cu;
GO
