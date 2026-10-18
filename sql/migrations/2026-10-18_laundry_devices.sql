-- ============================================================
-- 2026-10-18: GMO Laundry — ESP32 machine controllers.
--
--   laundryDevices     one row per controller (ESP32) wired to one machine.
--                      priceMXN is what one use costs; the device never sends
--                      an amount. keyHash = sha256(deviceKey) hex — the plain
--                      key is shown once when the device is created/rotated.
--   laundryDeviceUses  one row per authorize request. (deviceId, requestId) is
--                      the idempotency key: the ESP32 retries with the same
--                      requestId and gets the original answer. A QR token
--                      (tokenId) can only back one pending/authorized use.
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
    priceMXN         DECIMAL(12,2)  NOT NULL,
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
    CONSTRAINT CK_laundryDevices_machineType CHECK (machineType IN ('washer','dryer')),
    CONSTRAINT CK_laundryDevices_price CHECK (priceMXN > 0),
    CONSTRAINT CK_laundryDevices_cycle CHECK (cycleMinutes BETWEEN 1 AND 240)
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
    tokenId        NVARCHAR(40)   NOT NULL,
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

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_laundryDeviceUses_token')
    CREATE INDEX IX_laundryDeviceUses_token ON [dbo].[laundryDeviceUses] (tokenId, status);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_laundryDeviceUses_company')
    CREATE INDEX IX_laundryDeviceUses_company ON [dbo].[laundryDeviceUses] (companyId, created_At DESC);
GO

-- ============================================================
-- sp_laundryDevices
--   action 1  create      { companyId, branchId?, name, machineType, priceMXN, cycleMinutes?, keyHash }
--   action 2  update      { deviceId, companyId, name?, branchId?, priceMXN?, cycleMinutes?, isActive? }
--   action 3  rotate key  { deviceId, companyId, keyHash }
--   action 4  auth        { deviceId }  -> device WITH keyHash (internal: modules/laundryDevices.py)
--   action 5  heartbeat   { deviceId, status?, firmwareVersion?, ip?, rssi? }
-- Every action except 4 returns the device without keyHash.
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
        DECLARE @priceMXN        DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.laundryDevices[0].priceMXN'))
        DECLARE @cycleMinutes    INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].cycleMinutes'))
        DECLARE @isActive        BIT           = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].isActive'))
        DECLARE @keyHash         CHAR(64)      = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].keyHash')
        DECLARE @status          NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].status')
        DECLARE @firmwareVersion NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].firmwareVersion')
        DECLARE @ip              NVARCHAR(45)  = JSON_VALUE(@pjsonfile, '$.laundryDevices[0].ip')
        DECLARE @rssi            INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDevices[0].rssi'))

        IF @action = 1
        BEGIN
            IF @companyId IS NULL OR @name IS NULL OR @machineType IS NULL OR @priceMXN IS NULL OR @keyHash IS NULL
            BEGIN
                SELECT '{"error":"companyId, name, machineType, priceMXN y keyHash son requeridos"}' AS [jsonResult]
                RETURN
            END
            INSERT INTO [dbo].[laundryDevices] (companyId, branchId, name, machineType, priceMXN, cycleMinutes, keyHash)
            VALUES (@companyId, @branchId, @name, @machineType, @priceMXN, ISNULL(@cycleMinutes, 45), @keyHash)
            SET @deviceId = SCOPE_IDENTITY()
        END
        ELSE IF @action = 2
        BEGIN
            UPDATE [dbo].[laundryDevices]
            SET name         = ISNULL(@name, name),
                branchId     = ISNULL(@branchId, branchId),
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
                (SELECT deviceId, companyId, branchId, name, machineType, priceMXN, cycleMinutes,
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
        ELSE
        BEGIN
            SELECT '{"error":"action no soportada"}' AS [jsonResult]
            RETURN
        END

        SELECT ISNULL(
            (SELECT deviceId, companyId, branchId, name, machineType, priceMXN, cycleMinutes,
                    CAST(isActive AS INT) AS isActive, lastStatus, firmwareVersion, lastIp, lastRssi,
                    CONVERT(NVARCHAR, lastSeenAtUtc, 127) AS lastSeenAtUtc,
                    CONVERT(NVARCHAR, SYSUTCDATETIME(), 127) AS serverTimeUtc
             FROM [dbo].[laundryDevices] WHERE deviceId = @deviceId
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
        (SELECT deviceId, companyId, branchId, name, machineType, priceMXN, cycleMinutes,
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
--   action 1  open    { deviceId, companyId, clientId, requestId, tokenId, amountMXN }
--             Same (deviceId, requestId) again -> the stored use with replayed = 1
--             (a different tokenId under it -> request_conflict). A tokenId that
--             already backs another pending/authorized use -> token_used.
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
        DECLARE @tokenId       NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].tokenId')
        DECLARE @amountMXN     DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].amountMXN'))
        DECLARE @status        NVARCHAR(12)  = JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].status')
        DECLARE @reason        NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].reason')
        DECLARE @ledgerEntryId INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].ledgerEntryId'))
        DECLARE @balanceAfter  DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.laundryDeviceUses[0].balanceAfter'))
        DECLARE @replayed      INT           = 0

        IF @action = 1
        BEGIN
            BEGIN TRANSACTION;

            -- Lock the request key and the token so two retries / two machines
            -- can't both open a use for the same thing.
            SELECT @useId = useId FROM [dbo].[laundryDeviceUses] WITH (UPDLOCK, HOLDLOCK)
            WHERE deviceId = @deviceId AND requestId = @requestId

            IF @useId IS NOT NULL
            BEGIN
                COMMIT TRANSACTION;
                IF EXISTS (SELECT 1 FROM [dbo].[laundryDeviceUses] WHERE useId = @useId AND tokenId <> @tokenId)
                BEGIN
                    SELECT '{"error":"request_conflict"}' AS [jsonResult]
                    RETURN
                END
                SET @replayed = 1
            END
            ELSE
            BEGIN
                IF EXISTS (SELECT 1 FROM [dbo].[laundryDeviceUses] WITH (UPDLOCK, HOLDLOCK)
                           WHERE tokenId = @tokenId AND status IN ('pending','authorized'))
                BEGIN
                    ROLLBACK TRANSACTION;
                    SELECT '{"error":"token_used"}' AS [jsonResult]
                    RETURN
                END

                INSERT INTO [dbo].[laundryDeviceUses] (deviceId, companyId, clientId, requestId, tokenId, amountMXN)
                VALUES (@deviceId, @companyId, @clientId, @requestId, @tokenId, @amountMXN)
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
            (SELECT useId, deviceId, companyId, clientId, requestId, amountMXN, status, reason,
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
                u.amountMXN, u.status, u.reason, u.ledgerEntryId, u.balanceAfter,
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
