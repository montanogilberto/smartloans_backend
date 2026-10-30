-- =============================================================================
-- POS menu (companyId = 1, Lavandería): sizes of the option choices
-- =============================================================================
-- Data only, re-runnable. Source: the owner's products.xlsx (2026-10-27), column
-- "we need to add (measurements.name)". Prices and the choices the sheet does not
-- list (Agua, Bonafont, Refrescos, Persil…) are left exactly as they are.
--
-- WHY: productOptionChoices.quantity / measurementId were NULL for every choice,
--      so the POS could not tell a 600 ml Té Negro from a 450 ml Mango, or a 19 L
--      garrafón refill from a 3 L one.
-- WHAT: sets quantity + measurementId (dbo.measurements.prefix) for the choices
--       below, matched by product / option / choice NAME (a wizard save recreates
--       choice ids), and only where the size is still empty — a size typed later in
--       the product wizard is never overwritten.
-- Readers: sp_products_by_company / sp_products_one return it as quantity + unit.
-- ROLLBACK: not needed for data that was NULL; to undo, set quantity and
--           measurementId back to NULL for these same rows.
-- =============================================================================

SET NOCOUNT ON;

DECLARE @sizes TABLE (product NVARCHAR(255), optionName NVARCHAR(255), choice NVARCHAR(255),
                      quantity DECIMAL(10,3), unit VARCHAR(10));
INSERT INTO @sizes VALUES
    (N'Bebidas',            N'Te Arizona', N'Te Negro', 600, 'ml'),
    (N'Bebidas',            N'Te Arizona', N'Mango',    450, 'ml'),
    (N'Bebidas',            N'Te Arizona', N'Sandia',   450, 'ml'),
    (N'Garrafon Agua',      N'Tamaño',     N'19 lts',   19,  'L'),
    (N'Garrafon Agua',      N'Tamaño',     N'10 lts',   10,  'L'),
    (N'Garrafon Agua',      N'Tamaño',     N'3 lts',    3,   'L'),
    (N'Productos Limpieza', N'Jabon',      N'Generico', 100, 'ml'),
    (N'Productos Limpieza', N'Jabon',      N'Ariel',    100, 'ml');

UPDATE ch
SET ch.quantity = s.quantity,
    ch.measurementId = m.measurementId,
    ch.updatedAt = GETDATE()
FROM dbo.productOptionChoices ch
JOIN dbo.productOptions o ON o.productOptionId = ch.productOptionId
JOIN dbo.products p ON p.productId = o.productId AND p.companyId = 1
JOIN @sizes s ON s.product = p.name AND s.optionName = o.name AND s.choice = ch.name
JOIN dbo.measurements m ON m.prefix = s.unit
WHERE ch.quantity IS NULL AND ch.measurementId IS NULL;

PRINT CONCAT('Choices sized: ', @@ROWCOUNT);

-- Verify: every row of the sheet now has its size
SELECT p.name AS product, o.name AS optionName, ch.name AS choice, ch.price, ch.quantity, m.prefix AS unit
FROM dbo.productOptionChoices ch
JOIN dbo.productOptions o ON o.productOptionId = ch.productOptionId
JOIN dbo.products p ON p.productId = o.productId AND p.companyId = 1
LEFT JOIN dbo.measurements m ON m.measurementId = ch.measurementId
WHERE p.name IN (N'Bebidas', N'Garrafon Agua', N'Productos Limpieza')
ORDER BY p.name, o.name, ch.name;
