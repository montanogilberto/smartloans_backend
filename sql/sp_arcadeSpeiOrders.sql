-- ============================================================
-- arcadeChipOrders — comprar fichas por SPEI
-- ============================================================
-- SPEI NO SE COBRA, SE RECIBE. A diferencia de la tarjeta, aqui no podemos
-- ejecutar el cargo: el usuario empuja la transferencia desde su banco y
-- nosotros solo podemos detectarla. Por eso el flujo es:
--
--   1. se crea una ORDEN pendiente con una referencia unica
--   2. el usuario transfiere poniendo esa referencia en el concepto
--   3. declara su claveRastreo (la llave de rastreo del SPEI)
--   4. alguien AUTORIZADO confirma  ->  recien ahi se acreditan las fichas
--
-- EL PASO 4 NO LO PUEDE HACER EL PAGADOR. Si bastara con que el usuario
-- dijera "ya pague", cualquiera se regalaria fichas escribiendo una clave
-- inventada. La confirmacion la hace la conciliacion bancaria o un
-- administrador contra el estado de cuenta.
--
-- claveRastreo es la llave de idempotencia: es unica por transferencia en
-- SPEI y permite regenerar el CEP en Banxico, asi que sirve de comprobante y
-- de candado a la vez.
--
-- Sigue siendo dinero -> fichas, en un solo sentido. No hay canje.
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'arcadeChipOrders')
CREATE TABLE [dbo].[arcadeChipOrders] (
    orderId       INT IDENTITY PRIMARY KEY,
    companyId     INT            NOT NULL,
    clientId      INT            NOT NULL,
    packKey       NVARCHAR(40)   NOT NULL,
    chips         INT            NOT NULL,
    amountMXN     DECIMAL(12,2)  NOT NULL,
    -- Va en el concepto de la transferencia; es como se casa el deposito.
    reference     NVARCHAR(24)   NOT NULL,
    status        NVARCHAR(20)   NOT NULL DEFAULT 'pending',
                  -- pending | declared | confirmed | rejected | expired
    claveRastreo  NVARCHAR(40)   NULL,
    declaredAt    DATETIME2      NULL,
    confirmedAt   DATETIME2      NULL,
    confirmedBy   INT            NULL,      -- userId que concilio
    rejectReason  NVARCHAR(200)  NULL,
    expiresAt     DATETIME2      NOT NULL,
    created_At    DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at    DATETIME2      NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UX_arcadeChipOrders_ref')
    CREATE UNIQUE INDEX UX_arcadeChipOrders_ref ON [dbo].[arcadeChipOrders] (reference);
GO

-- Una misma transferencia no puede pagar dos ordenes.
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UX_arcadeChipOrders_clave')
    CREATE UNIQUE INDEX UX_arcadeChipOrders_clave
        ON [dbo].[arcadeChipOrders] (claveRastreo) WHERE claveRastreo IS NOT NULL;
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_arcadeChipOrders_client')
    CREATE INDEX IX_arcadeChipOrders_client
        ON [dbo].[arcadeChipOrders] (companyId, clientId, created_At DESC);
GO

-- ============================================================
-- sp_arcadeChipOrders_create — abre la orden (NO acredita nada)
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeChipOrders_create', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeChipOrders_create;
GO

CREATE PROCEDURE [dbo].[sp_arcadeChipOrders_create]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT           = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].companyId')
        DECLARE @clientId  INT           = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].clientId')
        DECLARE @packKey   NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].packKey')
        DECLARE @chips     INT           = TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].chips') AS INT)
        DECLARE @amount    DECIMAL(12,2) = TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].amountMXN') AS DECIMAL(12,2))
        DECLARE @reference NVARCHAR(24)  = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].reference')
        DECLARE @hours     INT           = ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].expiresInHours') AS INT), 48)
        DECLARE @orderId INT

        IF @companyId IS NULL OR @clientId IS NULL OR @reference IS NULL OR @amount IS NULL OR @chips IS NULL
        BEGIN
            SELECT '{"error":"missing_fields","message":"Faltan datos de la orden"}' AS [jsonResult]
            RETURN
        END

        -- Las pendientes viejas se marcan vencidas para que el cliente no
        -- acumule referencias vivas que ya no piensa pagar.
        UPDATE [dbo].[arcadeChipOrders]
        SET status = 'expired', updated_at = GETUTCDATE()
        WHERE companyId = @companyId AND clientId = @clientId
          AND status = 'pending' AND expiresAt < GETUTCDATE()

        INSERT INTO [dbo].[arcadeChipOrders]
            (companyId, clientId, packKey, chips, amountMXN, reference, expiresAt)
        VALUES
            (@companyId, @clientId, @packKey, @chips, @amount, @reference,
             DATEADD(HOUR, @hours, GETUTCDATE()))
        SET @orderId = SCOPE_IDENTITY()

        SELECT (SELECT TOP 1 orderId, packKey, chips, amountMXN, reference, status,
                       CONVERT(NVARCHAR, expiresAt, 127) AS expiresAt
                FROM [dbo].[arcadeChipOrders] WHERE orderId = @orderId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeChipOrders_declare — el usuario dice que ya transfirio
-- ============================================================
-- SOLO deja constancia. NO acredita fichas: lo que el pagador afirma no es
-- prueba de nada, y creerle seria regalar fichas a quien invente una clave.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeChipOrders_declare', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeChipOrders_declare;
GO

CREATE PROCEDURE [dbo].[sp_arcadeChipOrders_declare]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @orderId INT          = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].orderId')
        DECLARE @clientId INT         = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].clientId')
        DECLARE @clave   NVARCHAR(40) = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].claveRastreo')

        IF @clave IS NULL OR LEN(LTRIM(RTRIM(@clave))) < 6
        BEGIN
            SELECT '{"error":"bad_clave","message":"La clave de rastreo no es valida"}' AS [jsonResult]
            RETURN
        END

        IF EXISTS (SELECT 1 FROM [dbo].[arcadeChipOrders]
                   WHERE claveRastreo = @clave AND orderId <> @orderId)
        BEGIN
            SELECT '{"error":"clave_already_used","message":"Esa transferencia ya se uso en otra orden"}' AS [jsonResult]
            RETURN
        END

        UPDATE [dbo].[arcadeChipOrders]
        SET claveRastreo = @clave, status = 'declared',
            declaredAt = GETUTCDATE(), updated_at = GETUTCDATE()
        WHERE orderId = @orderId AND clientId = @clientId
          AND status IN ('pending', 'declared') AND expiresAt >= GETUTCDATE()

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT '{"error":"order_not_open","message":"Esa orden ya no acepta comprobante"}' AS [jsonResult]
            RETURN
        END

        SELECT '{"status":"declared","orderId":' + CAST(@orderId AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeChipOrders_confirm — concilia y ACREDITA
-- ============================================================
-- El unico sitio donde una orden SPEI entrega fichas. Lo llama la
-- conciliacion bancaria o un administrador CONTRA EL ESTADO DE CUENTA; nunca
-- el pagador.
--
-- Todo va en UNA transaccion —orden confirmada, compra registrada, monedero
-- abonado, libro escrito— porque partirlo dejaria al cliente pagado y sin
-- fichas, o con fichas sin registro de compra.
--
-- La idempotencia real la da UX_arcadePurchases_tx sobre
-- (platform, storeTransactionId) = ('spei', 'spei:<claveRastreo>'): reconfirmar
-- no vuelve a acreditar.
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeChipOrders_confirm', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeChipOrders_confirm;
GO

CREATE PROCEDURE [dbo].[sp_arcadeChipOrders_confirm]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @orderId     INT           = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].orderId')
        DECLARE @confirmedBy INT           = TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].confirmedBy') AS INT)
        -- Monto realmente recibido segun el banco. Si no viene, se toma el de
        -- la orden; si viene y no cuadra, se rechaza.
        DECLARE @received    DECIMAL(12,2) = TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].receivedMXN') AS DECIMAL(12,2))

        DECLARE @companyId INT, @clientId INT, @packKey NVARCHAR(40)
        DECLARE @chips INT, @amount DECIMAL(12,2), @clave NVARCHAR(40), @status NVARCHAR(20)
        DECLARE @walletId INT, @balance INT, @purchaseId INT, @folio NVARCHAR(40)
        DECLARE @storeTx NVARCHAR(120)

        BEGIN TRANSACTION
            SELECT @companyId = companyId, @clientId = clientId, @packKey = packKey,
                   @chips = chips, @amount = amountMXN, @clave = claveRastreo, @status = status
            FROM [dbo].[arcadeChipOrders] WITH (UPDLOCK, HOLDLOCK)
            WHERE orderId = @orderId

            IF @companyId IS NULL
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"order_not_found","message":"Esa orden no existe"}' AS [jsonResult]
                RETURN
            END
            IF @status = 'confirmed'
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"status":"already_confirmed","orderId":' + CAST(@orderId AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END
            IF @clave IS NULL
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"no_clave","message":"La orden no tiene clave de rastreo"}' AS [jsonResult]
                RETURN
            END
            -- Pagar de menos no compra el paquete: sin esta comprobacion se
            -- podria mandar un peso y reclamar las fichas completas.
            IF @received IS NOT NULL AND @received < @amount
            BEGIN
                ROLLBACK TRANSACTION
                SELECT '{"error":"amount_mismatch","message":"El deposito no cubre el monto de la orden","expected":' +
                       CAST(@amount AS NVARCHAR) + ',"received":' + CAST(@received AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

            SET @storeTx = 'spei:' + @clave

            IF EXISTS (SELECT 1 FROM [dbo].[arcadePurchases] WITH (UPDLOCK, HOLDLOCK)
                       WHERE platform = 'spei' AND storeTransactionId = @storeTx)
            BEGIN
                UPDATE [dbo].[arcadeChipOrders]
                SET status = 'confirmed', confirmedAt = GETUTCDATE(),
                    confirmedBy = @confirmedBy, updated_at = GETUTCDATE()
                WHERE orderId = @orderId
                COMMIT TRANSACTION
                SELECT '{"status":"already_credited","orderId":' + CAST(@orderId AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

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

            SET @balance = @balance + @chips

            INSERT INTO [dbo].[arcadePurchases]
                (companyId, clientId, packKey, platform, productId, storeTransactionId,
                 storeOriginalTransactionId, chipsCredited, priceCharged, currency, environment)
            VALUES
                (@companyId, @clientId, @packKey, 'spei', 'spei:' + @packKey, @storeTx,
                 @clave, @chips, ISNULL(@received, @amount), 'MXN', 'production')
            SET @purchaseId = SCOPE_IDENTITY()

            SET @folio = 'AR-' + RIGHT('000000' + CAST(@purchaseId AS NVARCHAR), 6)
            UPDATE [dbo].[arcadePurchases] SET folio = @folio WHERE purchaseId = @purchaseId

            UPDATE [dbo].[arcadeWallets]
            SET coinBalance = @balance, updated_at = GETUTCDATE()
            WHERE walletId = @walletId

            INSERT INTO [dbo].[arcadeTransactions]
                (companyId, clientId, walletId, txType, amount, balanceAfter, description)
            VALUES
                (@companyId, @clientId, @walletId, 'purchase', @chips, @balance,
                 'Compra de fichas por SPEI: ' + @packKey)

            UPDATE [dbo].[arcadeChipOrders]
            SET status = 'confirmed', confirmedAt = GETUTCDATE(),
                confirmedBy = @confirmedBy, updated_at = GETUTCDATE()
            WHERE orderId = @orderId
        COMMIT TRANSACTION

        SELECT '{"status":"credited","orderId":' + CAST(@orderId AS NVARCHAR) +
               ',"purchaseId":' + CAST(@purchaseId AS NVARCHAR) +
               ',"folio":"' + @folio + '"' +
               ',"chipsCredited":' + CAST(@chips AS NVARCHAR) +
               ',"coinBalance":' + CAST(@balance AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_arcadeChipOrders_all — ordenes del cliente / bandeja de conciliacion
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadeChipOrders_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadeChipOrders_all;
GO

CREATE PROCEDURE [dbo].[sp_arcadeChipOrders_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT          = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].companyId')
        DECLARE @clientId  INT          = TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].clientId') AS INT)
        DECLARE @status    NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].status')
        DECLARE @top       INT          = ISNULL(TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadeChipOrders[0].top') AS INT), 50)

        SELECT ISNULL(
            (SELECT TOP (@top) orderId, clientId, packKey, chips, amountMXN, reference,
                    status, claveRastreo,
                    CONVERT(NVARCHAR, declaredAt, 127)  AS declaredAt,
                    CONVERT(NVARCHAR, confirmedAt, 127) AS confirmedAt,
                    CONVERT(NVARCHAR, expiresAt, 127)   AS expiresAt,
                    CONVERT(NVARCHAR, created_At, 127)  AS created_At
             FROM [dbo].[arcadeChipOrders]
             WHERE companyId = @companyId
               AND (@clientId IS NULL OR clientId = @clientId)
               AND (@status IS NULL OR status = @status)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('arcadeChipOrders')),
            '{"arcadeChipOrders":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
