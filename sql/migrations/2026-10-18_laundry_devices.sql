-- ============================================================
-- 2026-10-18: GMO Laundry — ESP32 machine controllers.
--
--   laundryDevices     one row per controller (ESP32) wired to one machine.
--                      productId links it to the POS catalog (1002 Servicio de
--                      lavado, 1003 Servicio de secado): the client picks a cycle
--                      (productOptionChoices) on the machine's screen, the ESP32
--                      sends it and the use costs that choice's price. Without productId
--                      the use costs the fixed priceMXN. The device never sends
--                      an amount. keyHash = sha256(deviceKey) hex — the plain
--                      key is shown once when the device is created/rotated.
--   laundryDeviceUses  one row per authorize request. (deviceId, requestId) is
--                      the idempotency key: the ESP32 retries with the same
--                      requestId and gets the original answer. The client is
--                      identified by their fixed signed QR (modules/laundryDevices.py);
--                      tokenId is a leftover of the first version and stays NULL.
--
-- The charge itself is a LAUNDRY_USAGE debit in dbo.walletTransactions with
-- idempotencyKey = 'laundry:<deviceId>:<requestId>' (see modules/laundryDevices.py).
--
-- Safe to re-run.
-- ============================================================

-- ── Ledger entry type ──
MERGE [dbo].[walletTransactions_entryType] AS t
USING (VALUES ('LAUNDRY_USAGE', 20, 'Client pays one laundry machine use (out, ESP32 controller)'))
    AS s (entryType, sortOrder, description)
ON t.entryType = s.entryType
WHEN NOT MATCHED THEN
    INSERT (entryType, sortOrder, description) VALUES (s.entryType, s.sortOrder, s.description);
GO

-- ── Table: laundryDevices ──
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'laundryDevices')
CREATE TABLE [dbo].[laundryDevices] (
    deviceId         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    companyId        INT            NOT NULL,
    branchId         INT            NULL,
    name             NVARCHAR(60)   NOT NULL,
    machineType      NVARCHAR(20)   NOT NULL,
    productId        INT            NULL,
    priceMXN         DECIMAL(12,2)  NULL,
    cycleMinutes     INT            NOT NULL CONSTRAINT DF_laundryDevices_cycleMinutes DEFAULT (45),
    keyHash          CHAR(64)       NOT NULL,
    isActive         BIT            NOT NULL CONSTRAINT DF_laundryDevices_isActive DEFAULT (1),
    lastSeenAtUtc    DATETIME2(0)   NULL,
    lastStatus       NVARCHAR(20)   NULL,
    firmwareVersion  NVARCHAR(30)   NULL,
    lastIp           NVARCHAR(45)   NULL,
    lastRssi         INT            NULL,
    created_At       DATETIME2(0)   NOT NULL CONSTRAINT DF_laundryDevices_created DEFAULT (SYSUTCDATETIME()),
    updated_At       DATETIME2(0)   NOT NULL CONSTRAINT DF_laundryDevices_updated DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_laundryDevices_machineType CHECK (machineType IN ('washer','dryer','combo')),
    CONSTRAINT CK_laundryDevices_price CHECK (priceMXN IS NULL OR priceMXN > 0),
    CONSTRAINT CK_laundryDevices_cycle CHECK (cycleMinutes BETWEEN 1 AND 240)
);
GO

-- Upgrade from the first version (fixed price only).
IF COL_LENGTH('dbo.laundryDevices', 'productId') IS NULL
    ALTER TABLE [dbo].[laundryDevices] ADD productId INT NULL;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.laundryDevices')
           AND name = 'priceMXN' AND is_nullable = 0)
BEGIN
    ALTER TABLE [dbo].[laundryDevices] DROP CONSTRAINT CK_laundryDevices_price;
    ALTER TABLE [dbo].[laundryDevices] ALTER COLUMN priceMXN DECIMAL(12,2) NULL;
    ALTER TABLE [dbo].[laundryDevices] ADD CONSTRAINT CK_laundryDevices_price CHECK (priceMXN IS NULL OR priceMXN > 0);
END
GO

-- Combo machines (wash + dry on one controller): allow machineType 'combo'.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_laundryDevices_machineType'
           AND definition NOT LIKE '%combo%')
BEGIN
    ALTER TABLE [dbo].[laundryDevices] DROP CONSTRAINT CK_laundryDevices_machineType;
    ALTER TABLE [dbo].[laundryDevices] ADD CONSTRAINT CK_laundryDevices_machineType
        CHECK (machineType IN ('washer','dryer','combo'));
END
GO

-- ── Table: laundryDeviceProducts ──
-- Products a device sells, one tab per row on the machine's screen (a combo
-- machine has Lavado 1002 + Secado 1003). When a device has rows here they
-- replace laundryDevices.productId; a device without rows keeps working with
-- its single productId (or fixed priceMXN).
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'laundryDeviceProducts')
CREATE TABLE [dbo].[laundryDeviceProducts] (
    deviceId    INT           NOT NULL,
    productId   INT           NOT NULL,
    label       NVARCHAR(30)  NULL,       -- tab text; NULL = product name
    sortOrder   INT           NOT NULL CONSTRAINT DF_laundryDeviceProducts_sort DEFAULT (0),
    CONSTRAINT PK_laundryDeviceProducts PRIMARY KEY (deviceId, productId),
    CONSTRAINT FK_laundryDeviceProducts_device FOREIGN KEY (deviceId) REFERENCES [dbo].[laundryDevices] (deviceId)
);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_laundryDevices_company')
    CREATE INDEX IX_laundryDevices_company ON [dbo].[laundryDevices] (companyId, isActive);
GO

-- ── Table: laundryDeviceUses ──
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'laundryDeviceUses')
CREATE TABLE [dbo].[laundryDeviceUses] (
    useId          INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    deviceId       INT            NOT NULL,
    companyId      INT            NOT NULL,
    clientId       INT            NOT NULL,
    requestId      NVARCHAR(40)   NOT NULL,
    tokenId        NVARCHAR(40)   NULL,
    productOptionChoiceId INT     NULL,
    choiceName     NVARCHAR(100)  NULL,
    amountMXN      DECIMAL(12,2)  NOT NULL,
    status         NVARCHAR(12)   NOT NULL CONSTRAINT DF_laundryDeviceUses_status DEFAULT ('pending'),
    reason         NVARCHAR(40)   NULL,
    ledgerEntryId  INT            NULL,
    balanceAfter   DECIMAL(12,2)  NULL,
    created_At     DATETIME2(0)   NOT NULL CONSTRAINT DF_laundryDeviceUses_created DEFAULT (SYSUTCDATETIME()),
    settled_At     DATETIME2(0)   NULL,
    CONSTRAINT FK_laundryDeviceUses_device FOREIGN KEY (deviceId) REFERENCES [dbo].[laundryDevices] (deviceId),
    CONSTRAINT UQ_laundryDeviceUses_request UNIQUE (deviceId, requestId),
    CONSTRAINT CK_laundryDeviceUses_status CHECK (status IN ('pending','authorized','rejected'))
);
GO

IF COL_LENGTH('dbo.laundryDeviceUses', 'productOptionChoiceId') IS NULL
    ALTER TABLE [dbo].[laundryDeviceUses] ADD productOptionChoiceId INT NULL, choiceName NVARCHAR(100) NULL;
GO

-- Upgrade from the single-use QR token version.
IF EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_laundryDeviceUses_token')
    DROP INDEX IX_laundryDeviceUses_token ON [dbo].[laundryDeviceUses];
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.laundryDeviceUses')
           AND name = 'tokenId' AND is_nullable = 0)
    ALTER TABLE [dbo].[laundryDeviceUses] ALTER COLUMN tokenId NVARCHAR(40) NULL;
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_laundryDeviceUses_company')
    CREATE INDEX IX_laundryDeviceUses_company ON [dbo].[laundryDeviceUses] (companyId, created_At DESC);
GO

-- ============================================================
-- sp_laundryDevices
--   action 1  create      { companyId, branchId?, name, machineType, productId? | products? | priceMXN, cycleMinutes?, keyHash }
--   action 2  update      { deviceId, companyId, name?, branchId?, productId?, products?, priceMXN?, cycleMinutes?, isActive? }
--             products = [{ productId, label? }] in tab order (combo: Lavado, Secado).
--             When sent, it replaces the device's laundryDeviceProducts rows and
--             productId becomes the first one.
--   action 3  rotate key  { deviceId, companyId, keyHash }
--   action 4  auth        { deviceId }  -> device WITH keyHash (internal: modules/laundryDevices.py)
--   action 5  heartbeat   { deviceId, status?, firmwareVersion?, ip?, rssi? }
--   action 6  price       { deviceId, productOptionChoiceId? } -> { priceMXN, productOptionChoiceId, choiceName, productId }
--   action 7  cycles      { deviceId } -> { cycles: [{ productOptionChoiceId, name, priceMXN, description,
--                                                   productId, groupLabel, groupOrder }] }
--             What the machine's screen offers: the priced choices of its products,
--             grouped by product (one tab per group).
--             description (productOptionChoices.description, edited in the POS)
--             is the screen's detail line, e.g. "Agua baja".
--   action 8  client      { deviceId, clientId } -> { clientId, firstName }
--             Only an active client of the device's company; the screen is public,
--             so it never returns the last name.
--             The choice must be an option of one of the device's products (same company).
--             A device without productId only accepts no choice (fixed priceMXN).
-- Actions 1, 2, 3 and 5 return the device without keyHash.
-- ============================================================
IF OBJECT_ID('dbo.sp_laundryDevices', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_laundryDevices;
GO
CREATE PROCEDURE [dbo].[sp_laundryDevices]
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
        DECLARE @productsJson    NVARCHAR(MAX) = JSON_QUERY(@pjsonfile, '$.laundryDevices[0].products')
        DECLARE @products TABLE (productId INT, label NVARCHAR(30), sortOrder INT)
        IF @productsJson IS NOT NULL
            INSERT INTO @products (productId, label, sortOrder)
            SELECT TRY_CONVERT(INT, JSON_VALUE(value, '$.productId')),
                   NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.label'))), ''),
                   TRY_CONVERT(INT, [key])
            FROM OPENJSON(@productsJson)
        IF @productsJson IS NOT NULL AND @productId IS NULL
            SELECT TOP 1 @productId = productId FROM @products ORDER BY sortOrder

        IF @action = 1
        BEGIN
            IF @companyId IS NULL OR @name IS NULL OR @machineType IS NULL OR @keyHash IS NULL
               OR (@productId IS NULL AND @priceMXN IS NULL)
            BEGIN
                SELECT '{"error":"companyId, name, machineType y productId, products o priceMXN son requeridos"}' AS [jsonResult]
                RETURN
            END
            IF EXISTS (SELECT 1 FROM @products x
                       WHERE x.productId IS NULL OR NOT EXISTS
                             (SELECT 1 FROM [dbo].[products] p WHERE p.productId = x.productId AND p.companyId = @companyId))
            BEGIN
                SELECT '{"error":"product_not_found"}' AS [jsonResult]
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
            INSERT INTO [dbo].[laundryDeviceProducts] (deviceId, productId, label, sortOrder)
            SELECT @deviceId, productId, label, sortOrder FROM @products
        END
        ELSE IF @action = 2
        BEGIN
            IF EXISTS (SELECT 1 FROM @products x
                       WHERE x.productId IS NULL OR NOT EXISTS
                             (SELECT 1 FROM [dbo].[products] p WHERE p.productId = x.productId AND p.companyId = @companyId))
            BEGIN
                SELECT '{"error":"product_not_found"}' AS [jsonResult]
                RETURN
            END
            UPDATE [dbo].[laundryDevices]
            SET name         = ISNULL(@name, name),
                machineType  = ISNULL(@machineType, machineType),
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
            IF @productsJson IS NOT NULL
            BEGIN
                DELETE FROM [dbo].[laundryDeviceProducts] WHERE deviceId = @deviceId
                INSERT INTO [dbo].[laundryDeviceProducts] (deviceId, productId, label, sortOrder)
                SELECT @deviceId, productId, label, sortOrder FROM @products
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

            -- the device's products: its laundryDeviceProducts rows, else productId
            DECLARE @devProducts TABLE (productId INT)
            INSERT INTO @devProducts SELECT productId FROM [dbo].[laundryDeviceProducts] WHERE deviceId = @deviceId
            IF NOT EXISTS (SELECT 1 FROM @devProducts) AND @devProductId IS NOT NULL
                INSERT INTO @devProducts VALUES (@devProductId)

            IF NOT EXISTS (SELECT 1 FROM @devProducts)
            BEGIN
                IF @choiceId IS NOT NULL OR @devPrice IS NULL
                    SELECT '{"error":"choice_not_for_device"}' AS [jsonResult]
                ELSE
                    SELECT (SELECT @devPrice AS priceMXN FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
                RETURN
            END

            SELECT ISNULL(
                (SELECT c.price AS priceMXN, c.productOptionChoiceId, c.name AS choiceName, o.productId
                 FROM [dbo].[productOptionChoices] c
                 JOIN [dbo].[productOptions] o ON o.productOptionId = c.productOptionId
                 JOIN [dbo].[products] p ON p.productId = o.productId
                 WHERE c.productOptionChoiceId = @choiceId
                   AND o.productId IN (SELECT productId FROM @devProducts)
                   AND p.companyId = @devCompanyId
                   AND c.price > 0
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{"error":"choice_not_for_device"}') AS [jsonResult]
            RETURN
        END
        ELSE IF @action = 7
        BEGIN
            DECLARE @groups TABLE (productId INT, label NVARCHAR(30), sortOrder INT)
            INSERT INTO @groups SELECT productId, label, sortOrder
            FROM [dbo].[laundryDeviceProducts] WHERE deviceId = @deviceId
            IF NOT EXISTS (SELECT 1 FROM @groups)
                INSERT INTO @groups SELECT productId, NULL, 0
                FROM [dbo].[laundryDevices] WHERE deviceId = @deviceId AND productId IS NOT NULL

            SELECT ISNULL(
                (SELECT c.productOptionChoiceId, c.name, c.price AS priceMXN, c.description,
                        p.productId, ISNULL(g.label, p.name) AS groupLabel, g.sortOrder AS groupOrder
                 FROM @groups g
                 JOIN [dbo].[laundryDevices] d ON d.deviceId = @deviceId
                 JOIN [dbo].[products] p ON p.productId = g.productId AND p.companyId = d.companyId
                 JOIN [dbo].[productOptions] o ON o.productId = p.productId
                 JOIN [dbo].[productOptionChoices] c ON c.productOptionId = o.productOptionId
                 WHERE c.price > 0
                 ORDER BY g.sortOrder, c.price, c.productOptionChoiceId
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
                    CONVERT(NVARCHAR, SYSUTCDATETIME(), 127) AS serverTimeUtc,
                    JSON_QUERY(ISNULL((SELECT x.productId, x.label FROM [dbo].[laundryDeviceProducts] x
                                       WHERE x.deviceId = d.deviceId ORDER BY x.sortOrder
                                       FOR JSON PATH), '[]')) AS products
             FROM [dbo].[laundryDevices] d WHERE deviceId = @deviceId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            '{"error":"device_not_found"}') AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_laundryDevices_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_laundryDevices_all;
GO
CREATE PROCEDURE [dbo].[sp_laundryDevices_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].companyId'))

    SELECT ISNULL(
        (SELECT deviceId, companyId, branchId, name, machineType, productId, priceMXN, cycleMinutes,
                CAST(isActive AS INT) AS isActive, lastStatus, firmwareVersion, lastIp, lastRssi,
                CONVERT(NVARCHAR, lastSeenAtUtc, 127) AS lastSeenAtUtc,
                CASE WHEN lastSeenAtUtc >= DATEADD(MINUTE, -3, SYSUTCDATETIME()) THEN 1 ELSE 0 END AS isOnline
         FROM [dbo].[laundryDevices]
         WHERE companyId = @companyId
         ORDER BY name
         FOR JSON PATH, ROOT('laundryDevices')),
        '{"laundryDevices":[]}') AS [jsonResult]
END
GO

-- ============================================================
-- sp_laundryDeviceUses
--   action 1  open    { deviceId, companyId, clientId, requestId, amountMXN,
--                       productOptionChoiceId?, choiceName? }
--             Same (deviceId, requestId) again -> the stored use with replayed = 1
--             (a different client or cycle under it -> request_conflict).
--   action 2  settle  { useId, status: authorized|rejected, reason?, ledgerEntryId?, balanceAfter? }
--             Only moves a pending use; a settled one is returned unchanged.
-- ============================================================
IF OBJECT_ID('dbo.sp_laundryDeviceUses', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_laundryDeviceUses;
GO
CREATE PROCEDURE [dbo].[sp_laundryDeviceUses]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action        INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].action'))
        DECLARE @useId         INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].useId'))
        DECLARE @deviceId      INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].deviceId'))
        DECLARE @companyId     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].companyId'))
        DECLARE @clientId      INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].clientId'))
        DECLARE @requestId     NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].requestId')
        DECLARE @amountMXN     DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].amountMXN'))
        DECLARE @choiceId      INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].productOptionChoiceId'))
        DECLARE @choiceName    NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].choiceName')
        DECLARE @status        NVARCHAR(12)  = JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].status')
        DECLARE @reason        NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].reason')
        DECLARE @ledgerEntryId INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].ledgerEntryId'))
        DECLARE @balanceAfter  DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].balanceAfter'))
        DECLARE @replayed      INT           = 0

        IF @action = 1
        BEGIN
            BEGIN TRANSACTION;

            -- Lock the request key so two retries can't both open a use.
            SELECT @useId = useId FROM [dbo].[laundryDeviceUses] WITH (UPDLOCK, HOLDLOCK)
            WHERE deviceId = @deviceId AND requestId = @requestId

            IF @useId IS NOT NULL
            BEGIN
                COMMIT TRANSACTION;
                IF EXISTS (SELECT 1 FROM [dbo].[laundryDeviceUses] WHERE useId = @useId
                           AND (clientId <> @clientId OR ISNULL(productOptionChoiceId, 0) <> ISNULL(@choiceId, 0)))
                BEGIN
                    SELECT '{"error":"request_conflict"}' AS [jsonResult]
                    RETURN
                END
                SET @replayed = 1
            END
            ELSE
            BEGIN
                INSERT INTO [dbo].[laundryDeviceUses]
                    (deviceId, companyId, clientId, requestId, productOptionChoiceId, choiceName, amountMXN)
                VALUES (@deviceId, @companyId, @clientId, @requestId, @choiceId, @choiceName, @amountMXN)
                SET @useId = SCOPE_IDENTITY()
                COMMIT TRANSACTION;
            END
        END
        ELSE IF @action = 2
        BEGIN
            UPDATE [dbo].[laundryDeviceUses]
            SET status = @status, reason = @reason, ledgerEntryId = @ledgerEntryId,
                balanceAfter = @balanceAfter, settled_At = SYSUTCDATETIME()
            WHERE useId = @useId AND status = 'pending' AND @status IN ('authorized','rejected')
        END
        ELSE
        BEGIN
            SELECT '{"error":"action no soportada"}' AS [jsonResult]
            RETURN
        END

        SELECT ISNULL(
            (SELECT useId, deviceId, companyId, clientId, requestId, productOptionChoiceId, choiceName,
                    amountMXN, status, reason,
                    ledgerEntryId, balanceAfter, @replayed AS replayed,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, settled_At, 127) AS settled_At
             FROM [dbo].[laundryDeviceUses] WHERE useId = @useId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            '{"error":"use_not_found"}') AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_laundryDeviceUses_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_laundryDeviceUses_all;
GO
CREATE PROCEDURE [dbo].[sp_laundryDeviceUses_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].companyId'))
    DECLARE @deviceId  INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].deviceId'))
    DECLARE @clientId  INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].clientId'))
    DECLARE @top       INT = ISNULL(TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].top')), 100)
    IF @top > 500 SET @top = 500

    SELECT ISNULL(
        (SELECT TOP (@top) u.useId, u.deviceId, d.name AS deviceName, d.machineType, u.clientId,
                u.productOptionChoiceId, u.choiceName, u.amountMXN, u.status, u.reason, u.ledgerEntryId, u.balanceAfter,
                CONVERT(NVARCHAR, u.created_At, 127) AS created_At,
                CONVERT(NVARCHAR, u.settled_At, 127) AS settled_At
         FROM [dbo].[laundryDeviceUses] u
         JOIN [dbo].[laundryDevices] d ON d.deviceId = u.deviceId
         WHERE u.companyId = @companyId
           AND (@deviceId IS NULL OR u.deviceId = @deviceId)
           AND (@clientId IS NULL OR u.clientId = @clientId)
         ORDER BY u.useId DESC
         FOR JSON PATH, ROOT('laundryDeviceUses')),
        '{"laundryDeviceUses":[]}') AS [jsonResult]
END
GO

-- ============================================================
-- sp_laundryClientQrs_list — clients whose fixed QR the batch regenerates
-- (POST /laundryDevices/regenerateClientQrs).
--   { companyId, clientIds?: [int], afterClientId?, top? }  -> { clients: [{ clientId }] }
-- Active clients of the company, by clientId, paged with afterClientId.
-- ============================================================
IF OBJECT_ID('dbo.sp_laundryClientQrs_list', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_laundryClientQrs_list;
GO
CREATE PROCEDURE [dbo].[sp_laundryClientQrs_list]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.clients[0].companyId'))
    DECLARE @after     INT = ISNULL(TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.clients[0].afterClientId')), 0)
    DECLARE @top       INT = ISNULL(TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.clients[0].top')), 200)
    DECLARE @ids       NVARCHAR(MAX) = JSON_QUERY(@pjsonfile, '$.clients[0].clientIds')
    IF @top > 500 SET @top = 500

    SELECT ISNULL(
        (SELECT TOP (@top) c.clientId
         FROM [dbo].[clients] c
         WHERE c.companyId = @companyId
           AND c.isActive = 1
           AND c.clientId > @after
           AND (@ids IS NULL OR c.clientId IN (SELECT TRY_CONVERT(INT, value) FROM OPENJSON(@ids)))
         ORDER BY c.clientId
         FOR JSON PATH, ROOT('clients')),
        '{"clients":[]}') AS [jsonResult]
END
GO
