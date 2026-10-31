-- =============================================================================
-- Lavandería (companyId = 1): length of each machine cycle
-- =============================================================================
-- Data only, re-runnable. Deploy AFTER sql/migrations/2026-10-18_laundry_devices.sql
-- (sp_laundryDevices actions 6/7 return cycleMinutes from these columns).
--
-- WHY: the ESP32 showed 45 min for every washer cycle: the backend only read
--      minutes from the choice NAME ("50 Min") and fell back to
--      laundryDevices.cycleMinutes (45) for "Basico", "Medio"…
-- WHAT: 1. adds the unit "min" to dbo.measurements (the POS product wizard lists it);
--       2. sets quantity + measurementId = minutes on the washer's cycle choices,
--          matched by product / option / choice NAME (a wizard save recreates ids).
--       Later changes are made in the POS: product → option → choice → Cant. + "min".
-- ROLLBACK: set quantity and measurementId back to NULL for these rows; the
--           measurement row can stay (unused units are harmless).
-- =============================================================================

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM dbo.measurements WHERE prefix = 'min')
    INSERT INTO dbo.measurements (name, prefix) VALUES ('Minutos', 'min');

DECLARE @minutes TABLE (product NVARCHAR(255), optionName NVARCHAR(255), choice NVARCHAR(255), minutes INT);
INSERT INTO @minutes VALUES
    (N'Servicio de lavado', N'Ciclo', N'Basico',         20),
    (N'Servicio de lavado', N'Ciclo', N'Medio',          35),
    (N'Servicio de lavado', N'Ciclo', N'Carga Alta',     50),
    (N'Servicio de lavado', N'Ciclo', N'Colcha Grandes', 65);

UPDATE ch
SET ch.quantity = s.minutes,
    ch.measurementId = m.measurementId,
    ch.updatedAt = GETDATE()
FROM dbo.productOptionChoices ch
JOIN dbo.productOptions o ON o.productOptionId = ch.productOptionId
JOIN dbo.products p ON p.productId = o.productId AND p.companyId = 1
JOIN @minutes s ON s.product = p.name AND s.optionName = o.name AND s.choice = ch.name
JOIN dbo.measurements m ON m.prefix = 'min';

PRINT CONCAT('Cycles timed: ', @@ROWCOUNT);

-- Verify: what each machine will show
SELECT p.name AS product, ch.name AS choice, ch.price, ch.quantity, m.prefix AS unit
FROM dbo.productOptionChoices ch
JOIN dbo.productOptions o ON o.productOptionId = ch.productOptionId
JOIN dbo.products p ON p.productId = o.productId AND p.companyId = 1
LEFT JOIN dbo.measurements m ON m.measurementId = ch.measurementId
WHERE p.name IN (N'Servicio de lavado', N'Servicio de secado')
ORDER BY p.name, ch.price;
