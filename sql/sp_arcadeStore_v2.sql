-- ============================================================
-- arcadeStore v2 — monto personalizado + ticket de compra
-- ============================================================
-- Se aplica DESPUES de sp_arcadeStore.sql. Todo es idempotente.
-- ============================================================

-- ── Monto personalizado ─────────────────────────────────────
-- El paquete 'custom' guarda la TARIFA, no un monto: `chips` es la unidad
-- base y `priceMXN` lo que cuesta esa unidad. El precio de una compra sale de
-- regla de tres en el backend, nunca del cliente.
IF COL_LENGTH('dbo.arcadeChipPacks', 'isCustom') IS NULL
    ALTER TABLE [dbo].[arcadeChipPacks] ADD isCustom NVARCHAR(1) NOT NULL DEFAULT '0';
GO
IF COL_LENGTH('dbo.arcadeChipPacks', 'minChips') IS NULL
    ALTER TABLE [dbo].[arcadeChipPacks] ADD minChips INT NULL;
GO
IF COL_LENGTH('dbo.arcadeChipPacks', 'maxChips') IS NULL
    ALTER TABLE [dbo].[arcadeChipPacks] ADD maxChips INT NULL;
GO

-- Tarifa: 1,000 fichas = $49.00 MXN (la misma del paquete starter, para que
-- el monto libre no salga mas barato que comprar el paquete chico).
MERGE [dbo].[arcadeChipPacks] AS t
USING (VALUES
    (1008, 'custom', 'Elige tu monto', 1000, 0, 49.00,
     'com.lavanderia.gmo.chips.custom', 'com.lavanderia.gmo.chips.custom',
     NULL, '1', 500, 50000, 5)
) AS s (companyId, packKey, name, chips, bonusChips, priceMXN,
        productIdIos, productIdAndroid, badge, isCustom, minChips, maxChips, sortOrder)
ON t.packKey = s.packKey
WHEN NOT MATCHED THEN
    INSERT (companyId, packKey, name, chips, bonusChips, priceMXN,
            productIdIos, productIdAndroid, badge, isCustom, minChips, maxChips, sortOrder)
    VALUES (s.companyId, s.packKey, s.name, s.chips, s.bonusChips, s.priceMXN,
            s.productIdIos, s.productIdAndroid, s.badge, s.isCustom, s.minChips, s.maxChips, s.sortOrder);
GO

-- ── Ticket de la compra ─────────────────────────────────────
-- folio: lo que ve el cliente en el correo. receiptUrl: el HTML en ADLS.
IF COL_LENGTH('dbo.arcadePurchases', 'folio') IS NULL
    ALTER TABLE [dbo].[arcadePurchases] ADD folio NVARCHAR(40) NULL;
GO
IF COL_LENGTH('dbo.arcadePurchases', 'receiptUrl') IS NULL
    ALTER TABLE [dbo].[arcadePurchases] ADD receiptUrl NVARCHAR(500) NULL;
GO
IF COL_LENGTH('dbo.arcadePurchases', 'receiptSentAt') IS NULL
    ALTER TABLE [dbo].[arcadePurchases] ADD receiptSentAt DATETIME2 NULL;
GO

-- ============================================================
-- sp_arcadeChipPacks_all — ahora incluye la tarifa del monto libre
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
                    productIdIos, productIdAndroid, badge, sortOrder,
                    isCustom, minChips, maxChips
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
-- sp_arcadePurchases_credit — v2: monto libre + folio
-- ============================================================
-- @chipsOverride solo lo manda el BACKEND, ya calculado. Aun asi la SP
-- revalida contra minChips/maxChips: si algun dia otro proceso llamara a esta
-- SP, el rango sigue siendo el de la base y no el que traiga el que llame.
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
        DECLARE @override   INT           = TRY_CAST(JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].chipsOverride') AS INT)

        DECLARE @chips INT, @bonus INT, @total INT, @isCustom NVARCHAR(1)
        DECLARE @minChips INT, @maxChips INT
        DECLARE @walletId INT, @balance INT, @purchaseId INT, @folio NVARCHAR(40)

        IF @companyId IS NULL OR @clientId IS NULL OR @storeTxId IS NULL OR @platform IS NULL
        BEGIN
            SELECT '{"error":"missing_fields","message":"Faltan datos de la compra"}' AS [jsonResult]
            RETURN
        END

        SELECT @chips = chips, @bonus = bonusChips, @isCustom = isCustom,
               @minChips = minChips, @maxChips = maxChips
        FROM [dbo].[arcadeChipPacks] WHERE packKey = @packKey AND isActive = '1'

        IF @chips IS NULL
        BEGIN
            SELECT '{"error":"unknown_pack","message":"Ese paquete no existe"}' AS [jsonResult]
            RETURN
        END

        IF @isCustom = '1'
        BEGIN
            IF @override IS NULL OR @override < @minChips OR @override > @maxChips
            BEGIN
                SELECT '{"error":"chips_out_of_range","message":"Cantidad de fichas fuera del rango permitido","minChips":' +
                       CAST(@minChips AS NVARCHAR) + ',"maxChips":' + CAST(@maxChips AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END
            SET @total = @override
        END
        ELSE
            SET @total = @chips + @bonus

        BEGIN TRANSACTION
            IF EXISTS (SELECT 1 FROM [dbo].[arcadePurchases] WITH (UPDLOCK, HOLDLOCK)
                       WHERE platform = @platform AND storeTransactionId = @storeTxId)
            BEGIN
                SELECT @balance = coinBalance FROM [dbo].[arcadeWallets]
                WHERE companyId = @companyId AND clientId = @clientId
                SELECT @folio = folio FROM [dbo].[arcadePurchases]
                WHERE platform = @platform AND storeTransactionId = @storeTxId
                ROLLBACK TRANSACTION
                SELECT '{"status":"already_credited","coinBalance":' +
                       CAST(ISNULL(@balance, 0) AS NVARCHAR) +
                       ',"folio":"' + ISNULL(@folio, '') + '"}' AS [jsonResult]
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

            SET @balance = @balance + @total

            INSERT INTO [dbo].[arcadePurchases]
                (companyId, clientId, packKey, platform, productId, storeTransactionId,
                 storeOriginalTransactionId, chipsCredited, priceCharged, currency, environment)
            VALUES
                (@companyId, @clientId, @packKey, @platform, @productId, @storeTxId,
                 @origTxId, @total, @price, @currency, @env)
            SET @purchaseId = SCOPE_IDENTITY()

            -- Folio legible para el cliente: AR-000123.
            SET @folio = 'AR-' + RIGHT('000000' + CAST(@purchaseId AS NVARCHAR), 6)
            UPDATE [dbo].[arcadePurchases] SET folio = @folio WHERE purchaseId = @purchaseId

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
               ',"folio":"' + @folio + '"' +
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
-- sp_arcadePurchases_receipt — guarda el ticket ya subido a ADLS
-- ============================================================
IF OBJECT_ID('dbo.sp_arcadePurchases_receipt', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_arcadePurchases_receipt;
GO

CREATE PROCEDURE [dbo].[sp_arcadePurchases_receipt]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @purchaseId INT           = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].purchaseId')
        DECLARE @url        NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].receiptUrl')
        DECLARE @sent       NVARCHAR(1)   = JSON_VALUE(@pjsonfile, '$.arcadePurchases[0].emailSent')

        UPDATE [dbo].[arcadePurchases]
        SET receiptUrl    = ISNULL(@url, receiptUrl),
            receiptSentAt = CASE WHEN @sent = '1' THEN GETUTCDATE() ELSE receiptSentAt END
        WHERE purchaseId = @purchaseId

        SELECT '{"message":"ok","purchaseId":' + CAST(@purchaseId AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
