-- ============================================================
-- arcadeStore — compra de fichas con dinero real (IAP)
-- ============================================================
-- SENTIDO UNICO: dinero -> fichas. NUNCA fichas -> dinero.
--
-- Ese sentido unico es lo que mantiene al arcade fuera del permiso SEGOB de
-- la Ley Federal de Juegos y Sorteos, que exige apuesta Y PREMIO: sin ruta de
-- canje no hay premio de valor economico, y el modelo es el de "casino
-- social" (Zynga, Coin Master), no el de casa de apuestas. Si algun dia se
-- agrega el canje, ESTE archivo no basta: hace falta permiso, geocerca y KYC.
--
-- El cobro NO pasa por Stripe. Apple (guia 3.1.1) y Google exigen que los
-- bienes digitales consumidos dentro de la app se vendan con StoreKit / Play
-- Billing; cobrar con Stripe hace que rechacen la build. Aqui solo se guarda
-- el resultado de una compra YA VERIFICADA contra los servidores de la
-- tienda en modules/arcadeStore.py.
--
-- IDEMPOTENCIA: un mismo storeTransactionId acredita fichas UNA sola vez. Es
-- el requisito de seguridad numero uno — reenviar un recibo no debe imprimir
-- fichas. Lo garantiza UX_arcadePurchases_tx, no la buena fe del cliente.
-- ============================================================

-- ── Tabla: arcadeChipPacks (catalogo de paquetes) ───────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'arcadeChipPacks')
CREATE TABLE [dbo].[arcadeChipPacks] (
    packId          INT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    packKey         NVARCHAR(40)   NOT NULL,
    name            NVARCHAR(60)   NOT NULL,
    chips           INT            NOT NULL,   -- fichas base
    bonusChips      INT            NOT NULL DEFAULT 0,
    -- Precio SOLO para pintar la tarjeta antes de que la tienda responda. El
    -- precio de verdad, con la moneda del pais del usuario, lo da StoreKit /
    -- Play Billing; nunca se cobra a partir de esta columna.
    priceMXN        DECIMAL(10,2)  NOT NULL,
    productIdIos     NVARCHAR(120) NOT NULL,
    productIdAndroid NVARCHAR(120) NOT NULL,
    badge           NVARCHAR(30)   NULL,       -- "Más popular", "Mejor valor"
    isActive        NVARCHAR(1)    NOT NULL DEFAULT '1',
    sortOrder       INT            NOT NULL DEFAULT 0,
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2      NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UX_arcadeChipPacks_key')
    CREATE UNIQUE INDEX UX_arcadeChipPacks_key ON [dbo].[arcadeChipPacks] (packKey);
GO

-- Los productId deben COINCIDIR con los que se den de alta en App Store
-- Connect y en Google Play Console, o la compra se verifica y se rechaza por
-- product_mismatch.
MERGE [dbo].[arcadeChipPacks] AS t
USING (VALUES
    (1008, 'starter', 'Puñado de fichas',  1000,     0,   49.00,
     'com.lavanderia.gmo.chips.starter', 'com.lavanderia.gmo.chips.starter', NULL,           1),
    (1008, 'popular', 'Bolsa de fichas',   5000,   500,  199.00,
     'com.lavanderia.gmo.chips.popular', 'com.lavanderia.gmo.chips.popular', 'Más popular',  2),
    (1008, 'pro',     'Cofre de fichas',  10000,  2000,  349.00,
     'com.lavanderia.gmo.chips.pro',     'com.lavanderia.gmo.chips.pro',     NULL,           3),
    (1008, 'mega',    'Baúl de fichas',   25000,  5000,  799.00,
     'com.lavanderia.gmo.chips.mega',    'com.lavanderia.gmo.chips.mega',    'Mejor valor',  4)
) AS s (companyId, packKey, name, chips, bonusChips, priceMXN, productIdIos, productIdAndroid, badge, sortOrder)
ON t.packKey = s.packKey
WHEN NOT MATCHED THEN
    INSERT (companyId, packKey, name, chips, bonusChips, priceMXN, productIdIos, productIdAndroid, badge, sortOrder)
    VALUES (s.companyId, s.packKey, s.name, s.chips, s.bonusChips, s.priceMXN,
            s.productIdIos, s.productIdAndroid, s.badge, s.sortOrder);
GO

-- ── Tabla: arcadePurchases (recibos verificados) ────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'arcadePurchases')
CREATE TABLE [dbo].[arcadePurchases] (
    purchaseId              INT IDENTITY PRIMARY KEY,
    companyId               INT            NOT NULL,
    clientId                INT            NOT NULL,
    packKey                 NVARCHAR(40)   NOT NULL,
    platform                NVARCHAR(10)   NOT NULL,   -- ios | android
    productId               NVARCHAR(120)  NOT NULL,
    storeTransactionId      NVARCHAR(120)  NOT NULL,   -- id de la tienda
    storeOriginalTransactionId NVARCHAR(120) NULL,
    chipsCredited           INT            NOT NULL,
    -- Lo que de verdad cobro la tienda, en su moneda. Se guarda para poder
    -- conciliar ingresos sin depender del precio de catalogo.
    priceCharged            DECIMAL(12,2)  NULL,
    currency                NVARCHAR(8)    NULL,
    environment             NVARCHAR(12)   NULL,       -- production | sandbox
    created_At              DATETIME2      NOT NULL DEFAULT GETUTCDATE()
)
GO

-- El candado de idempotencia: dos veces el mismo recibo = una sola compra.
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UX_arcadePurchases_tx')
    CREATE UNIQUE INDEX UX_arcadePurchases_tx
        ON [dbo].[arcadePurchases] (platform, storeTransactionId);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_arcadePurchases_client')
    CREATE INDEX IX_arcadePurchases_client
        ON [dbo].[arcadePurchases] (companyId, clientId, created_At DESC);
GO

-- ============================================================
-- sp_arcadeChipPacks_all — catalogo para la tienda
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeChipPacks_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeChipPacks_all;
GO

CREATE PROCEDURE [dbo].[sp_arcadeChipPacks_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT ISNULL(
            (SELECT packKey, name, chips, bonusChips, priceMXN,
                    productIdIos, productIdAndroid, badge, sortOrder
             FROM [dbo].[arcadeChipPacks]
             WHERE isActive = '1'
             ORDER BY sortOrder
             FOR JSON PATH, ROOT('arcadeChipPacks')),
            '{"arcadeChipPacks":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadePurchases_credit — acredita una compra YA VERIFICADA
-- ============================================================
-- Solo se llama desde modules/arcadeStore.py DESPUES de validar el recibo
-- contra Apple o Google. La SP no sabe verificar nada: su trabajo es que el
-- abono ocurra una sola vez y de forma atomica.
--
-- Reenviar un recibo ya usado NO es error: devuelve already_credited con el
-- saldo actual, porque el cliente reintenta de forma legitima cuando se cae
-- la red entre el cobro y el abono.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadePurchases_credit', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadePurchases_credit;
GO

CREATE PROCEDURE [dbo].[sp_arcadePurchases_credit]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId  INT           = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].companyId')
        DECLARE @clientId   INT           = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].clientId')
        DECLARE @packKey    NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].packKey')
        DECLARE @platform   NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].platform')
        DECLARE @productId  NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].productId')
        DECLARE @storeTxId  NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].storeTransactionId')
        DECLARE @origTxId   NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].storeOriginalTransactionId')
        DECLARE @price      DECIMAL(12,2) = TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].priceCharged') AS DECIMAL(12,2))
        DECLARE @currency   NVARCHAR(8)   = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].currency')
        DECLARE @env        NVARCHAR(12)  = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].environment')

        DECLARE @chips INT, @bonus INT, @total INT
        DECLARE @walletId INT, @balance INT, @purchaseId INT

        IF @companyId IS NULL OR @clientId IS NULL OR @storeTxId IS NULL OR @platform IS NULL
        BEGIN
            SELECT '{"error":"missing_fields","message":"Faltan datos de la compra"}' AS [jsonResult]
            RETURN
        END

        SELECT @chips = chips, @bonus = bonusChips
        FROM [dbo].[arcadeChipPacks] WHERE packKey = @packKey AND isActive = '1'

        IF @chips IS NULL
        BEGIN
            SELECT '{"error":"unknown_pack","message":"Ese paquete no existe"}' AS [jsonResult]
            RETURN
        END
        SET @total = @chips + @bonus

        BEGIN TRANSACTION
            -- HOLDLOCK sobre el indice unico: serializa dos abonos simultaneos
            -- del MISMO recibo (doble toque, o reintento mientras el primero
            -- sigue en vuelo) en vez de dejar que ambos pasen la comprobacion.
            IF EXISTS (SELECT 1 FROM [dbo].[arcadePurchases] WITH (UPDLOCK, HOLDLOCK)
                       WHERE platform = @platform AND storeTransactionId = @storeTxId)
            BEGIN
                SELECT @balance = coinBalance FROM [dbo].[arcadeWallets]
                WHERE companyId = @companyId AND clientId = @clientId
                ROLLBACK TRANSACTION
                SELECT '{"status":"already_credited","coinBalance":' +
                       CAST(ISNULL(@balance, 0) AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

            -- La compra puede llegar antes de que el jugador entre al arcade.
            SELECT @walletId = walletId, @balance = coinBalance
            FROM [dbo].[arcadeWallets] WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND clientId = @clientId

            IF @walletId IS NULL
            BEGIN
                INSERT INTO [dbo].[arcadeWallets] (companyId, clientId, coinBalance)
                VALUES (@companyId, @clientId, 0)
                SET @walletId = SCOPE_IDENTITY()
                SET @balance = 0
            END

            SET @balance = @balance + @total

            INSERT INTO [dbo].[arcadePurchases]
                (companyId, clientId, packKey, platform, productId, storeTransactionId,
                 storeOriginalTransactionId, chipsCredited, priceCharged, currency, environment)
            VALUES
                (@companyId, @clientId, @packKey, @platform, @productId, @storeTxId,
                 @origTxId, @total, @price, @currency, @env)
            SET @purchaseId = SCOPE_IDENTITY()

            UPDATE [dbo].[arcadeWallets]
            SET coinBalance = @balance, updated_at = GETUTCDATE()
            WHERE walletId = @walletId

            INSERT INTO [dbo].[arcadeTransactions]
                (companyId, clientId, walletId, txType, amount, balanceAfter, description)
            VALUES
                (@companyId, @clientId, @walletId, 'purchase', @total, @balance,
                 'Compra de fichas: ' + @packKey)
        COMMIT TRANSACTION

        SELECT '{"status":"credited","purchaseId":' + CAST(@purchaseId AS NVARCHAR) +
               ',"chipsCredited":' + CAST(@total AS NVARCHAR) +
               ',"coinBalance":' + CAST(@balance AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadePurchases_all — historial de compras del jugador
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadePurchases_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadePurchases_all;
GO

CREATE PROCEDURE [dbo].[sp_arcadePurchases_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].companyId')
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].clientId')
        DECLARE @top       INT = ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].top') AS INT), 50)

        SELECT ISNULL(
            (SELECT TOP (@top) purchaseId, packKey, platform, chipsCredited,
                    priceCharged, currency, environment,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM [dbo].[arcadePurchases]
             WHERE companyId = @companyId AND clientId = @clientId
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('arcadePurchases')),
            '{"arcadePurchases":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
