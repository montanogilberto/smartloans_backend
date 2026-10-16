-- =============================================================================
-- GMO Lavandería (companyId 1) — catalog: Categoría → Subcategoría → Producto
-- =============================================================================
-- NOT YET EXECUTED. Data script. Run manually against the live DB AFTER
-- 2026-10-15d_catalog_hierarchy.sql and 2026-10-15e_option_choice_measurements.sql.
-- Idempotent: categories are found-or-created by name, products by name; a
-- second run changes nothing.
--
-- WHAT (company 1 only):
--   1. Top-level categories: Servicios (reuses 1002 "Lavanderia" if not renamed
--      yet), Bebidas, Frituras, Limpieza. 1004 "Productos" is left as is (it keeps
--      the old pseudo-products; delete it from the app once empty).
--   2. Subcategories:
--        Servicios › Lavado, Secado, Servicio completo
--        Bebidas   › Agua purificada, Agua embotellada
--        Limpieza  › Bolsas, Detergentes y limpiadores, Suavizantes
--        Frituras  › (none yet)
--   3. Existing products moved: 1002 Servicio de lavado › Lavado, 1003 Servicio de
--      secado › Secado, 1004 + 2004 › Servicio completo, 3018 Garrafón › Agua
--      purificada. Their "Ciclo" / "Tamaño" options become radio + required; the
--      garrafón sizes get quantity + unit (19 / 10 / 3 L).
--   4. The choices of 1006 "Productos Limpieza" (Jabón, Suavisantes, Limpiadores)
--      become real products at the same price (sold per load: not inventory-
--      tracked), and 1006 is deactivated (kept: past sales point to it).
--   5. 3021 "Bolsas para empaque de ropa" → Limpieza › Bolsas as "Bolsa empaque
--      grande", sellable — ONLY when @bolsaPrecio is set below.
--   NOT TOUCHED: 1005 "Bebidas" (its options are still unknown) — Agua 1 litro /
--   Agua 500 ml come from it in a follow-up.
-- =============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('dbo.productCategories', 'parentCategoryId') IS NULL
   OR COL_LENGTH('dbo.productOptionChoices', 'measurementId') IS NULL
    BEGIN RAISERROR('Run 2026-10-15d_catalog_hierarchy.sql and 2026-10-15e_option_choice_measurements.sql first.', 16, 1); SET NOEXEC ON; RETURN; END
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ▼▼▼ Fill in, then run. NULL = step 5 is skipped (the bag stays a supply). ▼▼▼
DECLARE @bolsaPrecio DECIMAL(10,2) = NULL;   -- e.g. 15.00
-- ▲▲▲

DECLARE @companyId INT = 1;

BEGIN TRANSACTION;

-- 1) + 2) Categories ------------------------------------------------------------------------
DECLARE @cat TABLE (name VARCHAR(50) PRIMARY KEY, parentName VARCHAR(50) NULL, ord INT);
INSERT INTO @cat (name, parentName, ord) VALUES
    ('Servicios', NULL, 1), ('Bebidas', NULL, 2), ('Frituras', NULL, 3), ('Limpieza', NULL, 4),
    ('Lavado', 'Servicios', 11), ('Secado', 'Servicios', 12), ('Servicio completo', 'Servicios', 13),
    ('Agua purificada', 'Bebidas', 21), ('Agua embotellada', 'Bebidas', 22),
    ('Bolsas', 'Limpieza', 41), ('Detergentes y limpiadores', 'Limpieza', 42), ('Suavizantes', 'Limpieza', 43);

-- Servicios = the existing laundry category (1002) when it still has its old name.
IF NOT EXISTS (SELECT 1 FROM dbo.productCategories WHERE companyId = @companyId AND name = 'Servicios' AND parentCategoryId IS NULL)
   AND EXISTS (SELECT 1 FROM dbo.productCategories WHERE productCategoryId = 1002 AND companyId = @companyId AND name = 'Lavanderia')
    UPDATE dbo.productCategories SET name = 'Servicios' WHERE productCategoryId = 1002;

INSERT INTO dbo.productCategories (name, image, companyId, parentCategoryId)
SELECT c.name, NULL, @companyId, NULL
FROM @cat c
WHERE c.parentName IS NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.productCategories pc
                  WHERE pc.companyId = @companyId AND pc.name = c.name AND pc.parentCategoryId IS NULL);

INSERT INTO dbo.productCategories (name, image, companyId, parentCategoryId)
SELECT c.name, NULL, @companyId, p.productCategoryId
FROM @cat c
JOIN dbo.productCategories p
  ON p.companyId = @companyId AND p.name = c.parentName AND p.parentCategoryId IS NULL
WHERE c.parentName IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM dbo.productCategories pc
                  WHERE pc.companyId = @companyId AND pc.name = c.name AND pc.parentCategoryId = p.productCategoryId);

-- id of a subcategory by (parent, name)
DECLARE @sub TABLE (name VARCHAR(50) PRIMARY KEY, id INT NOT NULL);
INSERT INTO @sub (name, id)
SELECT s.name, s.productCategoryId
FROM dbo.productCategories s
JOIN dbo.productCategories p ON p.productCategoryId = s.parentCategoryId
JOIN @cat c ON c.name = s.name AND c.parentName = p.name
WHERE s.companyId = @companyId;

-- 3) Existing products → subcategories; options radio + required --------------------------
UPDATE p SET p.productCategoryId = s.id, p.updatedAt = GETDATE()
FROM dbo.products p
JOIN (VALUES (1002, 'Lavado'), (1003, 'Secado'), (1004, 'Servicio completo'),
             (2004, 'Servicio completo'), (3018, 'Agua purificada')) AS m(productId, subName)
  ON m.productId = p.productId
JOIN @sub s ON s.name = m.subName
WHERE p.companyId = @companyId
  AND ISNULL(p.productCategoryId, 0) <> s.id;

UPDATE o SET o.type = 'radio', o.isRequired = 1, o.updatedAt = GETDATE()
FROM dbo.productOptions o
JOIN dbo.products p ON p.productId = o.productId
WHERE p.companyId = @companyId
  AND p.productId IN (1002, 1003, 1004, 2004, 3018)
  AND o.name IN (N'Ciclo', N'Tamaño', N'Tamano')
  AND (o.type <> 'radio' OR o.isRequired = 0);

-- Garrafón sizes: "19 lts" → 19 L
UPDATE c SET c.quantity = TRY_CAST(LEFT(c.name, CHARINDEX(' ', c.name + ' ') - 1) AS DECIMAL(10,3)),
             c.measurementId = m.measurementId,
             c.updatedAt = GETDATE()
FROM dbo.productOptionChoices c
JOIN dbo.productOptions o ON o.productOptionId = c.productOptionId
JOIN dbo.measurements m ON m.prefix = 'L'
WHERE o.productId = 3018
  AND (c.name LIKE '% lts' OR c.name LIKE '% lt' OR c.name LIKE '% L')
  AND TRY_CAST(LEFT(c.name, CHARINDEX(' ', c.name + ' ') - 1) AS DECIMAL(10,3)) > 0
  AND (c.quantity IS NULL OR c.measurementId IS NULL);

-- 4) 1006 "Productos Limpieza" choices → real products ------------------------------------
DECLARE @new TABLE (name NVARCHAR(255) PRIMARY KEY, subName VARCHAR(50), price DECIMAL(10,2));
INSERT INTO @new (name, subName, price)
SELECT DISTINCT
    CASE
        WHEN o.name LIKE N'Jab%n' THEN N'Jabón ' + c.name
        -- "Suavisante Generico" → "Suavizante Generico"; brands (Suavitel, Ensueño) keep their name
        WHEN o.name LIKE N'Suavi%' AND c.name LIKE N'Suavi_ante %'
            THEN N'Suavizante ' + LTRIM(SUBSTRING(c.name, CHARINDEX(' ', c.name) + 1, 200))
        ELSE c.name
    END,
    CASE WHEN o.name LIKE N'Suavi%' THEN 'Suavizantes' ELSE 'Detergentes y limpiadores' END,
    c.price
FROM dbo.productOptions o
JOIN dbo.productOptionChoices c ON c.productOptionId = o.productOptionId
WHERE o.productId = 1006;

DECLARE @nextCode BIGINT = ISNULL((SELECT MAX(TRY_CAST(code AS BIGINT)) FROM dbo.products WITH (UPDLOCK, HOLDLOCK)
                                   WHERE companyId = @companyId), 0);
DECLARE @created TABLE (productId INT);

INSERT INTO dbo.products (name, code, description, createdAt, productCategoryId, companyId,
                          isSupply, trackInventory, isActive)
OUTPUT inserted.productId INTO @created (productId)
SELECT n.name,
       CAST(@nextCode + ROW_NUMBER() OVER (ORDER BY n.subName, n.name) AS VARCHAR(100)),
       N'Por carga', GETDATE(), s.id, @companyId,
       0, 0, 1          -- sold per load from bulk: not inventory-tracked
FROM @new n
JOIN @sub s ON s.name = n.subName
WHERE NOT EXISTS (SELECT 1 FROM dbo.products p WHERE p.companyId = @companyId AND p.name = n.name);

INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
SELECT p.productId, 0, 0, n.price, GETDATE(), GETDATE()
FROM @created c
JOIN dbo.products p ON p.productId = c.productId
JOIN @new n ON n.name = p.name;

UPDATE dbo.products SET isActive = 0, updatedAt = GETDATE()
WHERE productId = 1006 AND companyId = @companyId AND isActive = 1
  AND (SELECT COUNT(*) FROM @new) > 0;

-- 5) Bag → sellable product (only with a price) ---------------------------------------------
IF @bolsaPrecio IS NOT NULL
BEGIN
    UPDATE p SET p.name = N'Bolsa empaque grande', p.productCategoryId = s.id,
                 p.isSupply = 0, p.isActive = 1, p.updatedAt = GETDATE()
    FROM dbo.products p
    JOIN @sub s ON s.name = 'Bolsas'
    WHERE p.productId = 3021 AND p.companyId = @companyId;

    IF EXISTS (SELECT 1 FROM dbo.productDetails WHERE productId = 3021)
        UPDATE dbo.productDetails SET salePrice = @bolsaPrecio, updatedAt = GETDATE() WHERE productId = 3021;
    ELSE
        INSERT INTO dbo.productDetails (productId, stockQuantity, unitPrice, salePrice, createdAt, updatedAt)
        VALUES (3021, 0, 0, @bolsaPrecio, GETDATE(), GETDATE());
END
ELSE
    RAISERROR('Bolsa empaque grande skipped: set @bolsaPrecio and run again.', 0, 1) WITH NOWAIT;

COMMIT TRANSACTION;
SET XACT_ABORT OFF;

-- Verify --------------------------------------------------------------------------------------
SELECT ISNULL(parent.name + N' › ', N'') + c.name AS category, c.productCategoryId,
       (SELECT COUNT(*) FROM dbo.products p WHERE p.productCategoryId = c.productCategoryId AND p.isActive = 1) AS activeProducts
FROM dbo.productCategories c
LEFT JOIN dbo.productCategories parent ON parent.productCategoryId = c.parentCategoryId
WHERE c.companyId = 1
ORDER BY ISNULL(parent.name, c.name), CASE WHEN c.parentCategoryId IS NULL THEN 0 ELSE 1 END, c.name;

SELECT p.productId, p.name, cat.name AS subcategory, d.salePrice, p.isActive, p.isSupply, p.trackInventory
FROM dbo.products p
LEFT JOIN dbo.productCategories cat ON cat.productCategoryId = p.productCategoryId
OUTER APPLY (SELECT TOP 1 salePrice FROM dbo.productDetails WHERE productId = p.productId ORDER BY productDetailId) d
WHERE p.companyId = 1
ORDER BY cat.name, p.name;
GO

-- Re-enable execution (a failed pre-check above turns NOEXEC on for the rest of the file).
SET NOEXEC OFF;
GO
