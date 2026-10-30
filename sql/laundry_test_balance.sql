-- ============================================================
-- laundry_test_balance.sql — SALDO DE PRUEBA para las lavadoras ESP32.
--
-- Por qué: mientras no exista el monedero de la lavandería (RFC-009,
-- docs/rfcs/RFC-009-laundry-prepaid-wallet.md en POSVending), las máquinas
-- cobran de dbo.walletTransactions (POST /laundryDevices/quote y /authorize,
-- modules/laundryDevices.py). Este script carga saldo de PRUEBA a un cliente
-- para probar el flujo completo. NO es una recarga real: no hubo dinero.
--
-- Cómo: sólo usa sp_walletTransactions (INSERT-only, idempotente, sin
-- sobregiro). Nunca toca la tabla directo.
--
-- Uso (SSMS / Azure Data Studio, base de PRODUCCIÓN):
--   1. Cambia @clientId y @amountMXN.
--   2. Ejecuta el bloque 1 (cargar). Muestra el saldo antes y después.
--   3. Al terminar las pruebas, ejecuta el bloque 2 (dejar en $0).
-- Se puede correr varias veces: cada ejecución es un asiento nuevo con su
-- propia idempotencyKey (fecha y hora al segundo).
--
-- Rollback: el bloque 2 anula el saldo con un asiento REVERSAL (el libro no
-- permite borrar ni editar asientos).
-- ============================================================

-- ── Bloque 1: cargar saldo de prueba ──
DECLARE @companyId INT           = 1;      -- 1 = Lavandería
DECLARE @clientId  INT           = NULL;   -- <-- pon aquí el cliente de PRUEBA
DECLARE @amountMXN DECIMAL(12,2) = 200.00; -- <-- monto de prueba

IF @clientId IS NULL
    THROW 50001, N'Pon el @clientId del cliente de prueba.', 1;
IF @clientId = 1
    THROW 50002, N'El cliente 1 es "mostrador" (ventas sin cliente): no se le carga saldo.', 1;
IF @amountMXN <= 0 OR @amountMXN > 1000
    THROW 50003, N'@amountMXN debe ser mayor a 0 y máximo 1000 (es saldo de prueba).', 1;
IF NOT EXISTS (SELECT 1 FROM [dbo].[clients] WHERE clientId = @clientId AND companyId = @companyId AND isActive = 1)
    THROW 50004, N'El cliente no existe, no es de esta compañía o está inactivo.', 1;

DECLARE @key NVARCHAR(64) = CONCAT('laundry-test-c', @clientId, '-', FORMAT(SYSUTCDATETIME(), 'yyyyMMddHHmmss'));
DECLARE @balanceJson NVARCHAR(MAX) = CONCAT('{"walletTransactions":[{"companyId":', @companyId, ',"clientId":', @clientId, '}]}');
DECLARE @entryJson NVARCHAR(MAX) = CONCAT(
    '{"walletTransactions":[{"action":1,"companyId":', @companyId,
    ',"clientId":', @clientId,
    ',"entryType":"ADJUSTMENT","direction":"C","amountMXN":', @amountMXN,
    ',"idempotencyKey":"', @key, '"',
    ',"referenceType":"laundryTest","note":"Saldo de PRUEBA lavadoras ESP32 (sin dinero real)"}]}');

PRINT 'Saldo ANTES:';
EXEC [dbo].[sp_walletTransactions_balance] @pjsonfile = @balanceJson;
PRINT 'Asiento creado:';
EXEC [dbo].[sp_walletTransactions] @pjsonfile = @entryJson;
PRINT 'Saldo DESPUÉS:';
EXEC [dbo].[sp_walletTransactions_balance] @pjsonfile = @balanceJson;
GO


-- ── Bloque 2: al terminar las pruebas, dejar el saldo en $0 ──
-- Descomenta, pon el mismo @clientId y ejecuta sólo este bloque.
/*
DECLARE @companyId INT = 1;
DECLARE @clientId  INT = NULL;   -- <-- el mismo cliente de prueba

IF @clientId IS NULL THROW 50001, N'Pon el @clientId.', 1;

DECLARE @balanceJson NVARCHAR(MAX) = CONCAT('{"walletTransactions":[{"companyId":', @companyId, ',"clientId":', @clientId, '}]}');
DECLARE @available DECIMAL(12,2) = ISNULL(
    (SELECT TOP 1 balanceAfter FROM [dbo].[walletTransactions]
     WHERE companyId = @companyId AND clientId = @clientId
       AND entryType NOT IN ('CAPITAL_DECLARED','CAPITAL_COMMITTED','CAPITAL_UNDECLARED')
     ORDER BY entryId DESC), 0);

IF @available <= 0
    PRINT 'El saldo ya está en $0: no hay nada que anular.';
ELSE
BEGIN
    DECLARE @key NVARCHAR(64) = CONCAT('laundry-test-reset-c', @clientId, '-', FORMAT(SYSUTCDATETIME(), 'yyyyMMddHHmmss'));
    DECLARE @entryJson NVARCHAR(MAX) = CONCAT(
        '{"walletTransactions":[{"action":1,"companyId":', @companyId,
        ',"clientId":', @clientId,
        ',"entryType":"REVERSAL","direction":"D","amountMXN":', @available,
        ',"idempotencyKey":"', @key, '"',
        ',"referenceType":"laundryTest","note":"Fin de pruebas lavadoras ESP32: saldo de prueba anulado"}]}');
    EXEC [dbo].[sp_walletTransactions] @pjsonfile = @entryJson;
END
EXEC [dbo].[sp_walletTransactions_balance] @pjsonfile = @balanceJson;
*/
