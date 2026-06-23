-- ============================================================
-- Manufacturing Module — Laundry Machine Cost Tracking
-- Run once in Azure SQL. Order: this file first.
-- ============================================================

-- ── machines ────────────────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'machines')
CREATE TABLE [dbo].[machines] (
    machineId           INT IDENTITY PRIMARY KEY,
    companyId           INT NOT NULL,
    name                NVARCHAR(100) NOT NULL,
    machineType         NVARCHAR(30)  NOT NULL DEFAULT 'washer', -- washer | dryer | combo
    capacityKg          DECIMAL(8,2)  NOT NULL DEFAULT 0,
    kwhPerCycle         DECIMAL(8,4)  NOT NULL DEFAULT 0,   -- electricity per cycle
    litersPerCycle      DECIMAL(8,2)  NOT NULL DEFAULT 0,   -- water per cycle
    cycleMinutes        INT           NOT NULL DEFAULT 45,  -- avg cycle duration
    purchaseCost        DECIMAL(18,2) NOT NULL DEFAULT 0,
    lifetimeCycles      INT           NOT NULL DEFAULT 5000, -- expected total cycles
    currentCycleCount   INT           NOT NULL DEFAULT 0,
    maintenanceEvery    INT           NOT NULL DEFAULT 200,  -- cycles between services
    lastMaintenanceCycle INT          NOT NULL DEFAULT 0,
    wearScore           INT           NOT NULL DEFAULT 0,   -- 0-100, higher = more worn
    status              NVARCHAR(20)  NOT NULL DEFAULT 'available', -- available | in_use | maintenance | retired
    location            NVARCHAR(100) NULL,
    serialNumber        NVARCHAR(100) NULL,
    notes               NVARCHAR(500) NULL,
    createdAt           DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    updatedAt           DATETIME2     NULL,
)
GO

-- ── utilityRates ─────────────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'utilityRates')
CREATE TABLE [dbo].[utilityRates] (
    rateId              INT IDENTITY PRIMARY KEY,
    companyId           INT NOT NULL,
    electricityPerKwh   DECIMAL(10,4) NOT NULL DEFAULT 3.20,  -- MXN per kWh (CFE DAC avg)
    waterPerLiter       DECIMAL(10,4) NOT NULL DEFAULT 0.015, -- MXN per L (SIMAS avg)
    detergentPerGram    DECIMAL(10,4) NOT NULL DEFAULT 0.08,  -- MXN per gram
    laborPerHour        DECIMAL(10,2) NOT NULL DEFAULT 80.00, -- MXN per hour
    overheadPct         DECIMAL(5,2)  NOT NULL DEFAULT 15.00, -- % overhead on top
    targetMarginPct     DECIMAL(5,2)  NOT NULL DEFAULT 40.00, -- target profit margin %
    effectiveFrom       DATE          NOT NULL DEFAULT CAST(GETUTCDATE() AS DATE),
    createdAt           DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_utilityRates UNIQUE (companyId, effectiveFrom)
)
GO

-- ── productionOrders ─────────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'productionOrders')
CREATE TABLE [dbo].[productionOrders] (
    orderId             INT IDENTITY PRIMARY KEY,
    companyId           INT           NOT NULL,
    clientId            INT           NULL,
    ticketId            INT           NULL,  -- links to existing tickets table
    machineId           INT           NOT NULL,
    assignedBy          INT           NULL,  -- userId
    cycleType           NVARCHAR(30)  NOT NULL DEFAULT 'normal', -- delicate | normal | heavy | sanitize
    weightKg            DECIMAL(8,2)  NOT NULL DEFAULT 0,
    detergentGrams      DECIMAL(8,2)  NOT NULL DEFAULT 0,
    extraDetergent      BIT           NOT NULL DEFAULT 0,
    status              NVARCHAR(20)  NOT NULL DEFAULT 'queued', -- queued | running | done | cancelled
    startedAt           DATETIME2     NULL,
    completedAt         DATETIME2     NULL,
    estimatedMinutes    INT           NOT NULL DEFAULT 45,
    actualMinutes       INT           NULL,
    notes               NVARCHAR(500) NULL,
    -- cost snapshot (filled by CostEngine after cycle)
    realCostElec        DECIMAL(10,4) NULL,
    realCostWater       DECIMAL(10,4) NULL,
    realCostDetergent   DECIMAL(10,4) NULL,
    realCostLabor       DECIMAL(10,4) NULL,
    realCostDepreciation DECIMAL(10,4) NULL,
    realCostOverhead    DECIMAL(10,4) NULL,
    realCostTotal       DECIMAL(10,4) NULL,
    -- income link
    ticketPrice         DECIMAL(10,2) NULL,  -- what customer paid
    margin              DECIMAL(10,4) NULL,  -- ticketPrice - realCostTotal
    marginPct           DECIMAL(6,2)  NULL,
    -- alert flags
    alertSent           BIT           NOT NULL DEFAULT 0,
    maintenanceTriggered BIT          NOT NULL DEFAULT 0,
    createdAt           DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    updatedAt           DATETIME2     NULL,
)
GO

-- ── maintenanceLogs ──────────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'maintenanceLogs')
CREATE TABLE [dbo].[maintenanceLogs] (
    logId               INT IDENTITY PRIMARY KEY,
    companyId           INT           NOT NULL,
    machineId           INT           NOT NULL,
    logType             NVARCHAR(30)  NOT NULL DEFAULT 'scheduled', -- scheduled | emergency | inspection
    description         NVARCHAR(500) NULL,
    technicianName      NVARCHAR(100) NULL,
    costMXN             DECIMAL(10,2) NOT NULL DEFAULT 0,
    cycleAtMaintenance  INT           NOT NULL DEFAULT 0,
    wearBefore          INT           NOT NULL DEFAULT 0,
    wearAfter           INT           NOT NULL DEFAULT 0,
    partsReplaced       NVARCHAR(500) NULL,
    nextServiceCycle    INT           NULL,
    completedAt         DATETIME2     NULL,
    createdAt           DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
)
GO

-- ── profitabilitySnapshots ───────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'profitabilitySnapshots')
CREATE TABLE [dbo].[profitabilitySnapshots] (
    snapshotId          INT IDENTITY PRIMARY KEY,
    companyId           INT           NOT NULL,
    snapshotDate        DATE          NOT NULL DEFAULT CAST(GETUTCDATE() AS DATE),
    periodType          NVARCHAR(10)  NOT NULL DEFAULT 'daily', -- daily | weekly | monthly
    totalOrders         INT           NOT NULL DEFAULT 0,
    totalRevenue        DECIMAL(18,2) NOT NULL DEFAULT 0,
    totalRealCost       DECIMAL(18,2) NOT NULL DEFAULT 0,
    totalMargin         DECIMAL(18,2) NOT NULL DEFAULT 0,
    avgMarginPct        DECIMAL(6,2)  NOT NULL DEFAULT 0,
    bestServiceType     NVARCHAR(50)  NULL,
    worstServiceType    NVARCHAR(50)  NULL,
    lossOrders          INT           NOT NULL DEFAULT 0,
    suggestedPriceAdj   NVARCHAR(MAX) NULL,  -- JSON of suggested price changes
    createdAt           DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_profitSnap UNIQUE (companyId, snapshotDate, periodType)
)
GO

-- ============================================================
-- sp_machines
-- ============================================================
IF OBJECT_ID('dbo.sp_machines','P') IS NOT NULL DROP PROCEDURE dbo.sp_machines;
GO
CREATE PROCEDURE [dbo].[sp_machines]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         NVARCHAR(20)  = JSON_VALUE(@pjsonfile,'$.machines[0].action')
        DECLARE @machineId      INT           = JSON_VALUE(@pjsonfile,'$.machines[0].machineId')
        DECLARE @companyId      INT           = JSON_VALUE(@pjsonfile,'$.machines[0].companyId')
        DECLARE @name           NVARCHAR(100) = JSON_VALUE(@pjsonfile,'$.machines[0].name')
        DECLARE @machineType    NVARCHAR(30)  = JSON_VALUE(@pjsonfile,'$.machines[0].machineType')
        DECLARE @capacityKg     DECIMAL(8,2)  = JSON_VALUE(@pjsonfile,'$.machines[0].capacityKg')
        DECLARE @kwhPerCycle    DECIMAL(8,4)  = JSON_VALUE(@pjsonfile,'$.machines[0].kwhPerCycle')
        DECLARE @litersPerCycle DECIMAL(8,2)  = JSON_VALUE(@pjsonfile,'$.machines[0].litersPerCycle')
        DECLARE @cycleMinutes   INT           = JSON_VALUE(@pjsonfile,'$.machines[0].cycleMinutes')
        DECLARE @purchaseCost   DECIMAL(18,2) = JSON_VALUE(@pjsonfile,'$.machines[0].purchaseCost')
        DECLARE @lifetimeCycles INT           = JSON_VALUE(@pjsonfile,'$.machines[0].lifetimeCycles')
        DECLARE @maintenanceEvery INT         = JSON_VALUE(@pjsonfile,'$.machines[0].maintenanceEvery')
        DECLARE @status         NVARCHAR(20)  = JSON_VALUE(@pjsonfile,'$.machines[0].status')
        DECLARE @location       NVARCHAR(100) = JSON_VALUE(@pjsonfile,'$.machines[0].location')
        DECLARE @serialNumber   NVARCHAR(100) = JSON_VALUE(@pjsonfile,'$.machines[0].serialNumber')
        DECLARE @notes          NVARCHAR(500) = JSON_VALUE(@pjsonfile,'$.machines[0].notes')
        DECLARE @cycleIncrement INT           = JSON_VALUE(@pjsonfile,'$.machines[0].cycleIncrement')
        DECLARE @wearScore      INT           = JSON_VALUE(@pjsonfile,'$.machines[0].wearScore')

        IF @action = 'insert'
        BEGIN
            INSERT INTO [dbo].[machines]
                (companyId, name, machineType, capacityKg, kwhPerCycle, litersPerCycle,
                 cycleMinutes, purchaseCost, lifetimeCycles, maintenanceEvery, status, location, serialNumber, notes)
            VALUES
                (@companyId, @name, ISNULL(@machineType,'washer'), ISNULL(@capacityKg,0),
                 ISNULL(@kwhPerCycle,0), ISNULL(@litersPerCycle,0), ISNULL(@cycleMinutes,45),
                 ISNULL(@purchaseCost,0), ISNULL(@lifetimeCycles,5000), ISNULL(@maintenanceEvery,200),
                 ISNULL(@status,'available'), @location, @serialNumber, @notes)

            SELECT (SELECT SCOPE_IDENTITY() AS machineId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'update'
        BEGIN
            UPDATE [dbo].[machines] SET
                name            = ISNULL(@name, name),
                machineType     = ISNULL(@machineType, machineType),
                capacityKg      = ISNULL(@capacityKg, capacityKg),
                kwhPerCycle     = ISNULL(@kwhPerCycle, kwhPerCycle),
                litersPerCycle  = ISNULL(@litersPerCycle, litersPerCycle),
                cycleMinutes    = ISNULL(@cycleMinutes, cycleMinutes),
                purchaseCost    = ISNULL(@purchaseCost, purchaseCost),
                lifetimeCycles  = ISNULL(@lifetimeCycles, lifetimeCycles),
                maintenanceEvery= ISNULL(@maintenanceEvery, maintenanceEvery),
                status          = ISNULL(@status, status),
                location        = ISNULL(@location, location),
                serialNumber    = ISNULL(@serialNumber, serialNumber),
                notes           = ISNULL(@notes, notes),
                -- increment cycle counter if provided
                currentCycleCount = currentCycleCount + ISNULL(@cycleIncrement, 0),
                lastMaintenanceCycle = CASE WHEN @wearScore IS NOT NULL AND @wearScore < wearScore
                                           THEN currentCycleCount + ISNULL(@cycleIncrement,0)
                                           ELSE lastMaintenanceCycle END,
                wearScore       = ISNULL(@wearScore, wearScore),
                updatedAt       = GETUTCDATE()
            WHERE machineId = @machineId

            SELECT '{"message":"updated"}' AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT machineId, companyId, name, machineType, capacityKg, kwhPerCycle,
                        litersPerCycle, cycleMinutes, purchaseCost, lifetimeCycles,
                        currentCycleCount, maintenanceEvery, lastMaintenanceCycle, wearScore,
                        status, location, serialNumber, notes,
                        CONVERT(NVARCHAR, createdAt, 127) AS createdAt,
                        CONVERT(NVARCHAR, updatedAt, 127) AS updatedAt
                 FROM [dbo].[machines]
                 WHERE companyId = @companyId
                 ORDER BY name
                 FOR JSON PATH, ROOT('machines')),
                '{"machines":[]}'
            ) AS [jsonResult]
        END

        ELSE IF @action = 'one'
        BEGIN
            SELECT ISNULL(
                (SELECT machineId, companyId, name, machineType, capacityKg, kwhPerCycle,
                        litersPerCycle, cycleMinutes, purchaseCost, lifetimeCycles,
                        currentCycleCount, maintenanceEvery, lastMaintenanceCycle, wearScore,
                        status, location, serialNumber, notes,
                        CONVERT(NVARCHAR, createdAt, 127) AS createdAt
                 FROM [dbo].[machines]
                 WHERE machineId = @machineId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_productionOrders
-- ============================================================
IF OBJECT_ID('dbo.sp_productionOrders','P') IS NOT NULL DROP PROCEDURE dbo.sp_productionOrders;
GO
CREATE PROCEDURE [dbo].[sp_productionOrders]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         NVARCHAR(20)  = JSON_VALUE(@pjsonfile,'$.orders[0].action')
        DECLARE @orderId        INT           = JSON_VALUE(@pjsonfile,'$.orders[0].orderId')
        DECLARE @companyId      INT           = JSON_VALUE(@pjsonfile,'$.orders[0].companyId')
        DECLARE @clientId       INT           = JSON_VALUE(@pjsonfile,'$.orders[0].clientId')
        DECLARE @ticketId       INT           = JSON_VALUE(@pjsonfile,'$.orders[0].ticketId')
        DECLARE @machineId      INT           = JSON_VALUE(@pjsonfile,'$.orders[0].machineId')
        DECLARE @assignedBy     INT           = JSON_VALUE(@pjsonfile,'$.orders[0].assignedBy')
        DECLARE @cycleType      NVARCHAR(30)  = JSON_VALUE(@pjsonfile,'$.orders[0].cycleType')
        DECLARE @weightKg       DECIMAL(8,2)  = JSON_VALUE(@pjsonfile,'$.orders[0].weightKg')
        DECLARE @detergentGrams DECIMAL(8,2)  = JSON_VALUE(@pjsonfile,'$.orders[0].detergentGrams')
        DECLARE @extraDetergent BIT           = JSON_VALUE(@pjsonfile,'$.orders[0].extraDetergent')
        DECLARE @status         NVARCHAR(20)  = JSON_VALUE(@pjsonfile,'$.orders[0].status')
        DECLARE @startedAt      DATETIME2     = JSON_VALUE(@pjsonfile,'$.orders[0].startedAt')
        DECLARE @completedAt    DATETIME2     = JSON_VALUE(@pjsonfile,'$.orders[0].completedAt')
        DECLARE @actualMinutes  INT           = JSON_VALUE(@pjsonfile,'$.orders[0].actualMinutes')
        DECLARE @notes          NVARCHAR(500) = JSON_VALUE(@pjsonfile,'$.orders[0].notes')
        DECLARE @ticketPrice    DECIMAL(10,2) = JSON_VALUE(@pjsonfile,'$.orders[0].ticketPrice')
        DECLARE @realCostTotal  DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostTotal')
        DECLARE @realCostElec   DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostElec')
        DECLARE @realCostWater  DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostWater')
        DECLARE @realCostDet    DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostDetergent')
        DECLARE @realCostLabor  DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostLabor')
        DECLARE @realCostDeprec DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostDepreciation')
        DECLARE @realCostOvrh   DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].realCostOverhead')
        DECLARE @margin         DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.orders[0].margin')
        DECLARE @marginPct      DECIMAL(6,2)  = JSON_VALUE(@pjsonfile,'$.orders[0].marginPct')
        DECLARE @alertSent      BIT           = JSON_VALUE(@pjsonfile,'$.orders[0].alertSent')
        DECLARE @periodDays     INT           = ISNULL(JSON_VALUE(@pjsonfile,'$.orders[0].periodDays'), 30)

        IF @action = 'insert'
        BEGIN
            -- Validate machine is available
            IF NOT EXISTS (SELECT 1 FROM [dbo].[machines] WHERE machineId=@machineId AND status='available')
            BEGIN
                SELECT '{"error":"Machine not available"}' AS [jsonResult]
                RETURN
            END

            INSERT INTO [dbo].[productionOrders]
                (companyId, clientId, ticketId, machineId, assignedBy, cycleType,
                 weightKg, detergentGrams, extraDetergent, status, notes,
                 estimatedMinutes)
            SELECT @companyId, @clientId, @ticketId, @machineId, @assignedBy,
                   ISNULL(@cycleType,'normal'), ISNULL(@weightKg,0), ISNULL(@detergentGrams,0),
                   ISNULL(@extraDetergent,0), 'queued', @notes, cycleMinutes
            FROM [dbo].[machines] WHERE machineId = @machineId

            -- Mark machine as in_use
            UPDATE [dbo].[machines] SET status='in_use', updatedAt=GETUTCDATE() WHERE machineId=@machineId

            SELECT (SELECT SCOPE_IDENTITY() AS orderId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'start'
        BEGIN
            UPDATE [dbo].[productionOrders]
            SET status='running', startedAt=GETUTCDATE(), updatedAt=GETUTCDATE()
            WHERE orderId=@orderId
            SELECT '{"message":"started"}' AS [jsonResult]
        END

        ELSE IF @action = 'complete'
        BEGIN
            DECLARE @startTime DATETIME2 = (SELECT startedAt FROM [dbo].[productionOrders] WHERE orderId=@orderId)
            DECLARE @mins INT = DATEDIFF(MINUTE, @startTime, GETUTCDATE())

            UPDATE [dbo].[productionOrders]
            SET status='done', completedAt=GETUTCDATE(), actualMinutes=@mins,
                realCostElec=@realCostElec, realCostWater=@realCostWater,
                realCostDetergent=@realCostDet, realCostLabor=@realCostLabor,
                realCostDepreciation=@realCostDeprec, realCostOverhead=@realCostOvrh,
                realCostTotal=@realCostTotal, ticketPrice=@ticketPrice,
                margin=@margin, marginPct=@marginPct,
                updatedAt=GETUTCDATE()
            WHERE orderId=@orderId

            -- Free machine, increment cycle
            UPDATE [dbo].[machines]
            SET status='available',
                currentCycleCount = currentCycleCount + 1,
                updatedAt=GETUTCDATE()
            WHERE machineId = (SELECT machineId FROM [dbo].[productionOrders] WHERE orderId=@orderId)

            SELECT '{"message":"completed"}' AS [jsonResult]
        END

        ELSE IF @action = 'alert_sent'
        BEGIN
            UPDATE [dbo].[productionOrders] SET alertSent=1, updatedAt=GETUTCDATE() WHERE orderId=@orderId
            SELECT '{"message":"alert_sent"}' AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT o.orderId, o.companyId, o.clientId, o.ticketId, o.machineId,
                        o.cycleType, o.weightKg, o.detergentGrams, o.status,
                        o.estimatedMinutes, o.actualMinutes,
                        o.realCostTotal, o.ticketPrice, o.margin, o.marginPct,
                        o.alertSent,
                        CONVERT(NVARCHAR,o.startedAt,127)   AS startedAt,
                        CONVERT(NVARCHAR,o.completedAt,127) AS completedAt,
                        CONVERT(NVARCHAR,o.createdAt,127)   AS createdAt,
                        m.name AS machineName, m.machineType
                 FROM [dbo].[productionOrders] o
                 LEFT JOIN [dbo].[machines] m ON m.machineId = o.machineId
                 WHERE o.companyId = @companyId
                   AND o.createdAt >= DATEADD(DAY, -@periodDays, GETUTCDATE())
                 ORDER BY o.createdAt DESC
                 FOR JSON PATH, ROOT('orders')),
                '{"orders":[]}'
            ) AS [jsonResult]
        END

        ELSE IF @action = 'active'
        BEGIN
            -- Orders currently running or queued
            SELECT ISNULL(
                (SELECT o.orderId, o.machineId, o.clientId, o.cycleType, o.status,
                        o.estimatedMinutes, o.alertSent,
                        CONVERT(NVARCHAR,o.startedAt,127) AS startedAt,
                        m.name AS machineName, m.cycleMinutes
                 FROM [dbo].[productionOrders] o
                 JOIN [dbo].[machines] m ON m.machineId = o.machineId
                 WHERE o.companyId = @companyId AND o.status IN ('queued','running')
                 ORDER BY o.createdAt
                 FOR JSON PATH, ROOT('orders')),
                '{"orders":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_utilityRates
-- ============================================================
IF OBJECT_ID('dbo.sp_utilityRates','P') IS NOT NULL DROP PROCEDURE dbo.sp_utilityRates;
GO
CREATE PROCEDURE [dbo].[sp_utilityRates]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         NVARCHAR(10)  = JSON_VALUE(@pjsonfile,'$.rates[0].action')
        DECLARE @companyId      INT           = JSON_VALUE(@pjsonfile,'$.rates[0].companyId')
        DECLARE @elec           DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.rates[0].electricityPerKwh')
        DECLARE @water          DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.rates[0].waterPerLiter')
        DECLARE @det            DECIMAL(10,4) = JSON_VALUE(@pjsonfile,'$.rates[0].detergentPerGram')
        DECLARE @labor          DECIMAL(10,2) = JSON_VALUE(@pjsonfile,'$.rates[0].laborPerHour')
        DECLARE @overhead       DECIMAL(5,2)  = JSON_VALUE(@pjsonfile,'$.rates[0].overheadPct')
        DECLARE @margin         DECIMAL(5,2)  = JSON_VALUE(@pjsonfile,'$.rates[0].targetMarginPct')
        DECLARE @effFrom        DATE          = ISNULL(JSON_VALUE(@pjsonfile,'$.rates[0].effectiveFrom'), CAST(GETUTCDATE() AS DATE))

        IF @action = 'upsert'
        BEGIN
            MERGE [dbo].[utilityRates] AS t
            USING (SELECT @companyId AS companyId, @effFrom AS effectiveFrom) AS s
                ON t.companyId=s.companyId AND t.effectiveFrom=s.effectiveFrom
            WHEN MATCHED THEN UPDATE SET
                electricityPerKwh=ISNULL(@elec,t.electricityPerKwh),
                waterPerLiter=ISNULL(@water,t.waterPerLiter),
                detergentPerGram=ISNULL(@det,t.detergentPerGram),
                laborPerHour=ISNULL(@labor,t.laborPerHour),
                overheadPct=ISNULL(@overhead,t.overheadPct),
                targetMarginPct=ISNULL(@margin,t.targetMarginPct)
            WHEN NOT MATCHED THEN INSERT
                (companyId,electricityPerKwh,waterPerLiter,detergentPerGram,laborPerHour,overheadPct,targetMarginPct,effectiveFrom)
            VALUES (@companyId,ISNULL(@elec,3.20),ISNULL(@water,0.015),ISNULL(@det,0.08),
                    ISNULL(@labor,80),ISNULL(@overhead,15),ISNULL(@margin,40),@effFrom);

            SELECT (SELECT TOP 1 electricityPerKwh,waterPerLiter,detergentPerGram,
                           laborPerHour,overheadPct,targetMarginPct,
                           CONVERT(NVARCHAR,effectiveFrom,23) AS effectiveFrom
                    FROM [dbo].[utilityRates] WHERE companyId=@companyId
                    ORDER BY effectiveFrom DESC
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 rateId, electricityPerKwh, waterPerLiter, detergentPerGram,
                        laborPerHour, overheadPct, targetMarginPct,
                        CONVERT(NVARCHAR, effectiveFrom, 23) AS effectiveFrom
                 FROM [dbo].[utilityRates]
                 WHERE companyId=@companyId AND effectiveFrom <= CAST(GETUTCDATE() AS DATE)
                 ORDER BY effectiveFrom DESC
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{"electricityPerKwh":3.20,"waterPerLiter":0.015,"detergentPerGram":0.08,"laborPerHour":80,"overheadPct":15,"targetMarginPct":40}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_maintenanceLogs
-- ============================================================
IF OBJECT_ID('dbo.sp_maintenanceLogs','P') IS NOT NULL DROP PROCEDURE dbo.sp_maintenanceLogs;
GO
CREATE PROCEDURE [dbo].[sp_maintenanceLogs]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         NVARCHAR(10)  = JSON_VALUE(@pjsonfile,'$.logs[0].action')
        DECLARE @companyId      INT           = JSON_VALUE(@pjsonfile,'$.logs[0].companyId')
        DECLARE @machineId      INT           = JSON_VALUE(@pjsonfile,'$.logs[0].machineId')
        DECLARE @logType        NVARCHAR(30)  = JSON_VALUE(@pjsonfile,'$.logs[0].logType')
        DECLARE @description    NVARCHAR(500) = JSON_VALUE(@pjsonfile,'$.logs[0].description')
        DECLARE @techName       NVARCHAR(100) = JSON_VALUE(@pjsonfile,'$.logs[0].technicianName')
        DECLARE @costMXN        DECIMAL(10,2) = JSON_VALUE(@pjsonfile,'$.logs[0].costMXN')
        DECLARE @wearBefore     INT           = JSON_VALUE(@pjsonfile,'$.logs[0].wearBefore')
        DECLARE @wearAfter      INT           = JSON_VALUE(@pjsonfile,'$.logs[0].wearAfter')
        DECLARE @parts          NVARCHAR(500) = JSON_VALUE(@pjsonfile,'$.logs[0].partsReplaced')

        IF @action = 'insert'
        BEGIN
            DECLARE @currCycle INT = ISNULL((SELECT currentCycleCount FROM [dbo].[machines] WHERE machineId=@machineId), 0)
            DECLARE @nextService INT = @currCycle + ISNULL((SELECT maintenanceEvery FROM [dbo].[machines] WHERE machineId=@machineId), 200)

            INSERT INTO [dbo].[maintenanceLogs]
                (companyId, machineId, logType, description, technicianName, costMXN,
                 cycleAtMaintenance, wearBefore, wearAfter, partsReplaced, nextServiceCycle, completedAt)
            VALUES
                (@companyId, @machineId, ISNULL(@logType,'scheduled'), @description, @techName,
                 ISNULL(@costMXN,0), @currCycle, ISNULL(@wearBefore,0), ISNULL(@wearAfter,0),
                 @parts, @nextService, GETUTCDATE())

            -- Reset machine wear and update last maintenance
            UPDATE [dbo].[machines]
            SET wearScore=ISNULL(@wearAfter,0),
                lastMaintenanceCycle=@currCycle,
                status='available',
                updatedAt=GETUTCDATE()
            WHERE machineId=@machineId

            SELECT (SELECT SCOPE_IDENTITY() AS logId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT l.logId, l.machineId, l.logType, l.description, l.technicianName,
                        l.costMXN, l.cycleAtMaintenance, l.wearBefore, l.wearAfter,
                        l.partsReplaced, l.nextServiceCycle,
                        CONVERT(NVARCHAR, l.completedAt, 127) AS completedAt,
                        CONVERT(NVARCHAR, l.createdAt, 127)   AS createdAt,
                        m.name AS machineName
                 FROM [dbo].[maintenanceLogs] l
                 JOIN [dbo].[machines] m ON m.machineId=l.machineId
                 WHERE l.companyId=@companyId
                   AND (@machineId IS NULL OR l.machineId=@machineId)
                 ORDER BY l.createdAt DESC
                 FOR JSON PATH, ROOT('logs')),
                '{"logs":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_profitabilitySnapshots
-- ============================================================
IF OBJECT_ID('dbo.sp_profitabilitySnapshots','P') IS NOT NULL DROP PROCEDURE dbo.sp_profitabilitySnapshots;
GO
CREATE PROCEDURE [dbo].[sp_profitabilitySnapshots]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action     NVARCHAR(10) = JSON_VALUE(@pjsonfile,'$.snapshots[0].action')
        DECLARE @companyId  INT          = JSON_VALUE(@pjsonfile,'$.snapshots[0].companyId')
        DECLARE @periodType NVARCHAR(10) = ISNULL(JSON_VALUE(@pjsonfile,'$.snapshots[0].periodType'),'daily')
        DECLARE @snapDate   DATE         = ISNULL(JSON_VALUE(@pjsonfile,'$.snapshots[0].snapshotDate'), CAST(GETUTCDATE() AS DATE))
        DECLARE @limitRows  INT          = ISNULL(JSON_VALUE(@pjsonfile,'$.snapshots[0].limit'), 30)

        IF @action = 'upsert'
        BEGIN
            -- Aggregate from productionOrders for the period
            DECLARE @startDate DATE, @endDate DATE
            SET @endDate = @snapDate
            SET @startDate = CASE @periodType
                WHEN 'weekly'  THEN DATEADD(DAY,-6,@snapDate)
                WHEN 'monthly' THEN DATEADD(DAY,-29,@snapDate)
                ELSE @snapDate END

            SELECT
                @companyId AS companyId,
                COUNT(*)                                    AS totalOrders,
                ISNULL(SUM(ticketPrice),0)                  AS totalRevenue,
                ISNULL(SUM(realCostTotal),0)                AS totalRealCost,
                ISNULL(SUM(margin),0)                       AS totalMargin,
                ISNULL(AVG(marginPct),0)                    AS avgMarginPct,
                SUM(CASE WHEN margin < 0 THEN 1 ELSE 0 END) AS lossOrders
            INTO #snap
            FROM [dbo].[productionOrders]
            WHERE companyId=@companyId AND status='done'
              AND CAST(completedAt AS DATE) BETWEEN @startDate AND @endDate

            DECLARE @totOrd INT, @totRev DECIMAL(18,2), @totCost DECIMAL(18,2),
                    @totMrg DECIMAL(18,2), @avgMrg DECIMAL(6,2), @lossOrd INT
            SELECT @totOrd=totalOrders,@totRev=totalRevenue,@totCost=totalRealCost,
                   @totMrg=totalMargin,@avgMrg=avgMarginPct,@lossOrd=lossOrders FROM #snap
            DROP TABLE #snap

            -- Best / worst cycle type by margin
            DECLARE @best NVARCHAR(50), @worst NVARCHAR(50)
            SELECT TOP 1 @best=cycleType FROM [dbo].[productionOrders]
            WHERE companyId=@companyId AND status='done' AND CAST(completedAt AS DATE) BETWEEN @startDate AND @endDate
            GROUP BY cycleType ORDER BY AVG(marginPct) DESC

            SELECT TOP 1 @worst=cycleType FROM [dbo].[productionOrders]
            WHERE companyId=@companyId AND status='done' AND CAST(completedAt AS DATE) BETWEEN @startDate AND @endDate
            GROUP BY cycleType ORDER BY AVG(marginPct) ASC

            MERGE [dbo].[profitabilitySnapshots] AS t
            USING (SELECT @companyId AS companyId, @snapDate AS snapshotDate, @periodType AS periodType) AS s
                ON t.companyId=s.companyId AND t.snapshotDate=s.snapshotDate AND t.periodType=s.periodType
            WHEN MATCHED THEN UPDATE SET
                totalOrders=@totOrd, totalRevenue=@totRev, totalRealCost=@totCost,
                totalMargin=@totMrg, avgMarginPct=@avgMrg, lossOrders=@lossOrd,
                bestServiceType=@best, worstServiceType=@worst
            WHEN NOT MATCHED THEN INSERT
                (companyId,snapshotDate,periodType,totalOrders,totalRevenue,totalRealCost,
                 totalMargin,avgMarginPct,lossOrders,bestServiceType,worstServiceType)
            VALUES (@companyId,@snapDate,@periodType,@totOrd,@totRev,@totCost,
                    @totMrg,@avgMrg,@lossOrd,@best,@worst);

            SELECT '{"message":"snapshot saved"}' AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP (@limitRows)
                        snapshotId, snapshotDate, periodType, totalOrders,
                        totalRevenue, totalRealCost, totalMargin, avgMarginPct,
                        bestServiceType, worstServiceType, lossOrders
                 FROM [dbo].[profitabilitySnapshots]
                 WHERE companyId=@companyId AND periodType=@periodType
                 ORDER BY snapshotDate DESC
                 FOR JSON PATH, ROOT('snapshots')),
                '{"snapshots":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
