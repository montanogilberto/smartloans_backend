-- ============================================================
-- POS loyalty rewards — earn points from POS tickets, redeem
-- against an admin-managed catalog. Logically and structurally
-- separate from modules/rewards.py (loan-behavior rewardTransactions/
-- rewardBalances) and from any arcade chip ledger: no FK, no shared
-- endpoint, no conversion function between them.
--
-- Specs: posgmo-factory/tests/prd_posRewardProductRate.json,
--        prd_posRewardCatalogItem.json, prd_posRewardBalance.json,
--        prd_posRewardTransaction.json, prd_posRewardRedemption.json
--
-- Run this single file once against the target DB (tables use
-- IF NOT EXISTS, procedures DROP+CREATE, safe to re-run). Internal
-- order matters: posRewardBalances before posRewardTransactions/
-- posRewardRedemptions (they call sp_posRewardBalances_applyDelta),
-- posRewardCatalogItems before posRewardRedemptions (FK).
-- ============================================================

-- ── Table: posRewardProductRates ────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardProductRates')
CREATE TABLE [dbo].[posRewardProductRates] (
    rateId          INT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    productId       INT            NOT NULL,
    pointsPerUnit   DECIMAL(12,2)  NOT NULL,
    isActive        BIT            NOT NULL DEFAULT 1,
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2      NULL
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_posRewardProductRates_company_product')
    CREATE UNIQUE INDEX UQ_posRewardProductRates_company_product
        ON [dbo].[posRewardProductRates] (companyId, productId);
GO

-- ── Table: posRewardCatalogItems ────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardCatalogItems')
CREATE TABLE [dbo].[posRewardCatalogItems] (
    catalogItemId   INT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    name            NVARCHAR(120)  NOT NULL,
    rewardType      NVARCHAR(20)   NOT NULL,  -- discount_fixed | discount_pct | free_product
    requiredPoints  DECIMAL(12,2)  NOT NULL,
    discountValue   DECIMAL(12,2)  NULL,      -- MXN (discount_fixed) or 0-100 (discount_pct)
    freeProductId   INT            NULL,      -- required when rewardType='free_product'
    isActive        BIT            NOT NULL DEFAULT 1,
    description     NVARCHAR(255)  NULL,
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2      NULL,
    CONSTRAINT CK_posRewardCatalogItems_rewardType
        CHECK (rewardType IN ('discount_fixed','discount_pct','free_product')),
    CONSTRAINT CK_posRewardCatalogItems_valueByType CHECK (
        (rewardType IN ('discount_fixed','discount_pct') AND discountValue IS NOT NULL)
        OR (rewardType = 'free_product' AND freeProductId IS NOT NULL)
    )
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_posRewardCatalogItems_company')
    CREATE INDEX IX_posRewardCatalogItems_company
        ON [dbo].[posRewardCatalogItems] (companyId, isActive);
GO

-- ── Table: posRewardBalances (materialized projection) ──────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardBalances')
CREATE TABLE [dbo].[posRewardBalances] (
    balanceId        INT IDENTITY PRIMARY KEY,
    companyId        INT            NOT NULL,
    clientId         INT            NOT NULL,
    balance          DECIMAL(12,2)  NOT NULL DEFAULT 0,
    lifetimeEarned   DECIMAL(12,2)  NOT NULL DEFAULT 0,
    lifetimeRedeemed DECIMAL(12,2)  NOT NULL DEFAULT 0,
    lastActivity     DATETIME2      NULL
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_posRewardBalances_company_client')
    CREATE UNIQUE INDEX UQ_posRewardBalances_company_client
        ON [dbo].[posRewardBalances] (companyId, clientId);
GO

-- ── Table: posRewardTransactions (INSERT-only ledger) ───────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardTransactions')
CREATE TABLE [dbo].[posRewardTransactions] (
    transactionId   INT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    clientId        INT            NOT NULL,
    txType          NVARCHAR(20)   NOT NULL,  -- EARN | REDEEM | ADJUSTMENT | EXPIRE
    direction       NVARCHAR(1)    NOT NULL,  -- D=debit (balance down), C=credit (balance up)
    points          DECIMAL(12,2)  NOT NULL,  -- always positive; direction carries the sign
    referenceType   NVARCHAR(20)   NOT NULL,  -- ticket | redemption | manual
    referenceId     INT            NULL,      -- incomeId (ticket) / redemptionId (redemption) / NULL (manual)
    balanceAfter    DECIMAL(12,2)  NOT NULL,
    description     NVARCHAR(255)  NULL,
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT CK_posRewardTransactions_txType CHECK (txType IN ('EARN','REDEEM','ADJUSTMENT','EXPIRE')),
    CONSTRAINT CK_posRewardTransactions_direction CHECK (direction IN ('D','C')),
    CONSTRAINT CK_posRewardTransactions_referenceType CHECK (referenceType IN ('ticket','redemption','manual'))
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_posRewardTransactions_client_date')
    CREATE INDEX IX_posRewardTransactions_client_date
        ON [dbo].[posRewardTransactions] (clientId, created_At DESC);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_posRewardTransactions_reference')
    CREATE INDEX IX_posRewardTransactions_reference
        ON [dbo].[posRewardTransactions] (referenceType, referenceId);
GO
-- Idempotency: a retried earn-from-ticket call for the same (companyId, incomeId)
-- must be a no-op, never a duplicate EARN row. Filtered so redemption/manual
-- rows (referenceType<>'ticket') are unaffected.
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_posRewardTransactions_ticket')
    CREATE UNIQUE INDEX UQ_posRewardTransactions_ticket
        ON [dbo].[posRewardTransactions] (companyId, referenceId)
        WHERE referenceType = 'ticket';
GO

-- ── Table: posRewardRedemptions ─────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posRewardRedemptions')
CREATE TABLE [dbo].[posRewardRedemptions] (
    redemptionId     INT IDENTITY PRIMARY KEY,
    companyId        INT            NOT NULL,
    clientId         INT            NOT NULL,
    catalogItemId    INT            NOT NULL,
    pointsSpent      DECIMAL(12,2)  NOT NULL,
    status           NVARCHAR(20)   NOT NULL DEFAULT 'applied',  -- applied | cancelled
    incomeId         INT            NULL,
    redeemedByUserId INT            NOT NULL,
    created_At       DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT CK_posRewardRedemptions_status CHECK (status IN ('applied','cancelled')),
    CONSTRAINT FK_posRewardRedemptions_catalogItem
        FOREIGN KEY (catalogItemId) REFERENCES [dbo].[posRewardCatalogItems](catalogItemId)
)
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_posRewardRedemptions_client_date')
    CREATE INDEX IX_posRewardRedemptions_client_date
        ON [dbo].[posRewardRedemptions] (clientId, created_At DESC);
GO

-- ============================================================
-- sp_posRewardBalances_applyDelta — internal helper, not routed.
-- Upserts a client's balance inside the CALLER's transaction (no
-- BEGIN/COMMIT here) so earn/adjust/redeem stay atomic with their
-- ledger insert. Never called directly from a route.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardBalances_applyDelta', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardBalances_applyDelta;
GO
CREATE PROCEDURE [dbo].[sp_posRewardBalances_applyDelta]
    @companyId INT, @clientId INT,
    @pointsDelta DECIMAL(12,2),
    @earnedDelta DECIMAL(12,2) = 0,
    @redeemedDelta DECIMAL(12,2) = 0,
    @newBalance DECIMAL(12,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    MERGE [dbo].[posRewardBalances] AS tgt
    USING (SELECT @companyId AS companyId, @clientId AS clientId) AS src
        ON tgt.companyId = src.companyId AND tgt.clientId = src.clientId
    WHEN MATCHED THEN UPDATE SET
        balance = tgt.balance + @pointsDelta,
        lifetimeEarned = tgt.lifetimeEarned + @earnedDelta,
        lifetimeRedeemed = tgt.lifetimeRedeemed + @redeemedDelta,
        lastActivity = GETUTCDATE()
    WHEN NOT MATCHED THEN
        INSERT (companyId, clientId, balance, lifetimeEarned, lifetimeRedeemed, lastActivity)
        VALUES (@companyId, @clientId, @pointsDelta, @earnedDelta, @redeemedDelta, GETUTCDATE());

    SELECT @newBalance = balance FROM [dbo].[posRewardBalances]
    WHERE companyId = @companyId AND clientId = @clientId;
END
GO

-- ============================================================
-- sp_posRewardProductRates — action 0=read, 1=upsert (insert-or-
-- update on (companyId, productId), never a duplicate rate row).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardProductRates', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardProductRates;
GO
CREATE PROCEDURE [dbo].[sp_posRewardProductRates]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].action'));
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].companyId'));

    BEGIN TRY
        IF @action = 1
        BEGIN
            DECLARE @productId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].productId'));
            DECLARE @pointsPerUnit DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].pointsPerUnit'));
            DECLARE @isActive BIT = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].isActive'));

            IF @companyId IS NULL OR @productId IS NULL OR @pointsPerUnit IS NULL
                RAISERROR('companyId, productId y pointsPerUnit son requeridos.', 16, 1);

            MERGE [dbo].[posRewardProductRates] AS tgt
            USING (SELECT @companyId AS companyId, @productId AS productId) AS src
                ON tgt.companyId = src.companyId AND tgt.productId = src.productId
            WHEN MATCHED THEN UPDATE SET
                pointsPerUnit = @pointsPerUnit,
                isActive = ISNULL(@isActive, tgt.isActive),
                updated_at = GETUTCDATE()
            WHEN NOT MATCHED THEN
                INSERT (companyId, productId, pointsPerUnit, isActive)
                VALUES (@companyId, @productId, @pointsPerUnit, ISNULL(@isActive, 1));

            DECLARE @rateId INT = (SELECT rateId FROM [dbo].[posRewardProductRates] WHERE companyId=@companyId AND productId=@productId);
            SELECT ('{"result":[{"value":' + CAST(@rateId AS NVARCHAR(20)) + ',"msg":"Upserted Successfully","error":"0"}]}') AS [jsonResult]
        END
        ELSE IF @action IN (2,3)
            RAISERROR('Use action=1 (upsert) for posRewardProductRates.', 16, 1);
        ELSE
        BEGIN
            -- action 0 / read
            DECLARE @productIdFilter INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductRates[0].productId'));

            DECLARE @ratesJson NVARCHAR(MAX) = (
                SELECT rateId, companyId, productId, pointsPerUnit, isActive
                FROM [dbo].[posRewardProductRates]
                WHERE companyId = @companyId
                  AND (@productIdFilter IS NULL OR productId = @productIdFilter)
                ORDER BY productId
                FOR JSON PATH
            );
            SELECT ('{"result":[{"posRewardProductRates":' + ISNULL(@ratesJson, '[]') + '}]}') AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardCatalogItems — action 0=read, 1=insert, 2=update, 3=delete.
-- Simple CRUD — no immutability constraint (unlike posRewardTransactions).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardCatalogItems', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardCatalogItems;
GO
CREATE PROCEDURE [dbo].[sp_posRewardCatalogItems]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].action'));
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].companyId'));

    BEGIN TRY
        IF @action = 1
        BEGIN
            DECLARE @name NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].name');
            DECLARE @rewardType NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].rewardType');
            DECLARE @requiredPoints DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].requiredPoints'));
            DECLARE @discountValue DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].discountValue'));
            DECLARE @freeProductId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].freeProductId'));
            DECLARE @isActive BIT = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].isActive'));
            DECLARE @description NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].description');

            IF @companyId IS NULL OR @name IS NULL OR @rewardType IS NULL OR @requiredPoints IS NULL
                RAISERROR('companyId, name, rewardType y requiredPoints son requeridos.', 16, 1);

            INSERT INTO [dbo].[posRewardCatalogItems]
                (companyId, name, rewardType, requiredPoints, discountValue, freeProductId, isActive, description)
            VALUES
                (@companyId, @name, @rewardType, @requiredPoints, @discountValue, @freeProductId, ISNULL(@isActive,1), @description);

            DECLARE @newId INT = SCOPE_IDENTITY();
            SELECT ('{"result":[{"value":' + CAST(@newId AS NVARCHAR(20)) + ',"msg":"Inserted Successfully","error":"0"}]}') AS [jsonResult]
        END
        ELSE IF @action = 2
        BEGIN
            DECLARE @catalogItemId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].catalogItemId'));
            IF @catalogItemId IS NULL RAISERROR('catalogItemId es requerido.', 16, 1);

            UPDATE [dbo].[posRewardCatalogItems] SET
                name           = ISNULL(JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].name'), name),
                rewardType     = ISNULL(JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].rewardType'), rewardType),
                requiredPoints = ISNULL(TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].requiredPoints')), requiredPoints),
                discountValue  = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].discountValue')),
                freeProductId  = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].freeProductId')),
                isActive       = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].isActive')), isActive),
                description    = JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].description'),
                updated_at     = GETUTCDATE()
            WHERE catalogItemId = @catalogItemId AND companyId = @companyId;

            SELECT ('{"result":[{"value":' + CAST(@catalogItemId AS NVARCHAR(20)) + ',"msg":"Updated Successfully","error":"0"}]}') AS [jsonResult]
        END
        ELSE IF @action = 3
        BEGIN
            DECLARE @deleteId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].catalogItemId'));
            IF @deleteId IS NULL RAISERROR('catalogItemId es requerido.', 16, 1);

            DELETE FROM [dbo].[posRewardCatalogItems] WHERE catalogItemId = @deleteId AND companyId = @companyId;
            SELECT ('{"result":[{"value":' + CAST(@deleteId AS NVARCHAR(20)) + ',"msg":"Deleted Successfully","error":"0"}]}') AS [jsonResult]
        END
        ELSE
        BEGIN
            -- action 0 / read
            DECLARE @activeOnly BIT = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.posRewardCatalogItems[0].activeOnly'));
            DECLARE @itemsJson NVARCHAR(MAX) = (
                SELECT catalogItemId, companyId, name, rewardType, requiredPoints,
                       discountValue, freeProductId, isActive, description
                FROM [dbo].[posRewardCatalogItems]
                WHERE companyId = @companyId
                  AND (@activeOnly IS NULL OR @activeOnly = 0 OR isActive = 1)
                ORDER BY requiredPoints
                FOR JSON PATH
            );
            SELECT ('{"result":[{"posRewardCatalogItems":' + ISNULL(@itemsJson, '[]') + '}]}') AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardBalances — action 0/read ONLY (public). Writes happen
-- exclusively inside sp_posRewardTransactions_earnFromTicket/_adjust
-- and sp_posRewardRedemptions_redeem via sp_posRewardBalances_applyDelta.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardBalances', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardBalances;
GO
CREATE PROCEDURE [dbo].[sp_posRewardBalances]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].companyId'));
        DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].clientId'));
        IF @companyId IS NULL RAISERROR('companyId es requerido.', 16, 1);

        DECLARE @balancesJson NVARCHAR(MAX) = (
            SELECT companyId, clientId, balance, lifetimeEarned, lifetimeRedeemed,
                   CONVERT(NVARCHAR, lastActivity, 127) AS lastActivity
            FROM [dbo].[posRewardBalances]
            WHERE companyId = @companyId
              AND (@clientId IS NULL OR clientId = @clientId)
            ORDER BY balance DESC
            FOR JSON PATH
        );
        SELECT ('{"result":[{"posRewardBalances":' + ISNULL(@balancesJson, '[]') + '}]}') AS [jsonResult]
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardBalances_dashboardSummary — read-only, cross-table.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardBalances_dashboardSummary', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardBalances_dashboardSummary;
GO
CREATE PROCEDURE [dbo].[sp_posRewardBalances_dashboardSummary]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].companyId'));
    DECLARE @startDate DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].startDate'));
    DECLARE @endDate DATE = TRY_CONVERT(DATE, JSON_VALUE(@pjsonfile, '$.posRewardBalances[0].endDate'));

    DECLARE @pointsIssued DECIMAL(14,2), @pointsRedeemed DECIMAL(14,2);
    SELECT
        @pointsIssued = ISNULL(SUM(CASE WHEN direction = 'C' THEN points ELSE 0 END), 0),
        @pointsRedeemed = ISNULL(SUM(CASE WHEN direction = 'D' THEN points ELSE 0 END), 0)
    FROM [dbo].[posRewardTransactions]
    WHERE companyId = @companyId
      AND (@startDate IS NULL OR CONVERT(DATE, created_At) >= @startDate)
      AND (@endDate IS NULL OR CONVERT(DATE, created_At) <= @endDate);

    DECLARE @redemptionsCount INT = (
        SELECT COUNT(*) FROM [dbo].[posRewardRedemptions]
        WHERE companyId = @companyId AND status = 'applied'
          AND (@startDate IS NULL OR CONVERT(DATE, created_At) >= @startDate)
          AND (@endDate IS NULL OR CONVERT(DATE, created_At) <= @endDate)
    );

    DECLARE @topCustomersJson NVARCHAR(MAX) = (
        SELECT TOP 10 clientId, balance, lifetimeEarned
        FROM [dbo].[posRewardBalances]
        WHERE companyId = @companyId
        ORDER BY lifetimeEarned DESC
        FOR JSON PATH
    );

    DECLARE @activityJson NVARCHAR(MAX) = (
        SELECT CONVERT(NVARCHAR, CONVERT(DATE, created_At), 23) AS [date],
               SUM(CASE WHEN direction = 'C' THEN points ELSE 0 END) AS earned,
               SUM(CASE WHEN direction = 'D' THEN points ELSE 0 END) AS redeemed
        FROM [dbo].[posRewardTransactions]
        WHERE companyId = @companyId
          AND (@startDate IS NULL OR CONVERT(DATE, created_At) >= @startDate)
          AND (@endDate IS NULL OR CONVERT(DATE, created_At) <= @endDate)
        GROUP BY CONVERT(DATE, created_At)
        ORDER BY CONVERT(DATE, created_At)
        FOR JSON PATH
    );

    SELECT
        @pointsIssued AS pointsIssued,
        @pointsRedeemed AS pointsRedeemed,
        @redemptionsCount AS redemptionsCount,
        ISNULL(@topCustomersJson, '[]') AS topCustomersJson,
        ISNULL(@activityJson, '[]') AS activityJson
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
END
GO

-- ============================================================
-- sp_posRewardTransactions — action 0=read, 1=generic ledger insert
-- (e.g. future EXPIRE entries); 2/3 always rejected (INSERT-only ledger).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardTransactions', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardTransactions;
GO
CREATE PROCEDURE [dbo].[sp_posRewardTransactions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @action INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].action'));
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].companyId'));

    BEGIN TRY
        IF @action IN (2,3)
            RAISERROR('posRewardTransactions es un ledger INSERT-only. Usa una nueva entrada ADJUSTMENT/EXPIRE en su lugar.', 16, 1);
        ELSE IF @action = 1
        BEGIN
            RAISERROR('Usa sp_posRewardTransactions_earnFromTicket o _adjust para insertar en el ledger.', 16, 1);
        END
        ELSE
        BEGIN
            -- action 0 / read
            DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].clientId'));
            DECLARE @txType NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].txType');

            DECLARE @txJson NVARCHAR(MAX) = (
                SELECT transactionId, companyId, clientId, txType, direction, points,
                       referenceType, referenceId, balanceAfter, description,
                       CONVERT(NVARCHAR, created_At, 127) AS created_At
                FROM [dbo].[posRewardTransactions]
                WHERE companyId = @companyId
                  AND (@clientId IS NULL OR clientId = @clientId)
                  AND (@txType IS NULL OR txType = @txType)
                ORDER BY created_At DESC
                FOR JSON PATH
            );
            SELECT ('{"result":[{"posRewardTransactions":' + ISNULL(@txJson, '[]') + '}]}') AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardTransactions_earnFromTicket — the ONLY path allowed to
-- insert EARN rows. Idempotent per (companyId, incomeId): a retried
-- call for an already-posted ticket returns the existing result
-- instead of erroring or double-posting (UQ_posRewardTransactions_ticket
-- would otherwise raise a duplicate-key error under a race).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardTransactions_earnFromTicket', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardTransactions_earnFromTicket;
GO
CREATE PROCEDURE [dbo].[sp_posRewardTransactions_earnFromTicket]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].companyId'));
        DECLARE @incomeId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].incomeId'));

        IF @companyId IS NULL OR @incomeId IS NULL
            RAISERROR('companyId e incomeId son requeridos.', 16, 1);

        DECLARE @clientId INT = (SELECT clientId FROM [dbo].[income] WHERE incomeId = @incomeId AND companyId = @companyId);
        IF @clientId IS NULL
            RAISERROR('El ticket no existe para esta empresa.', 16, 1);

        -- Idempotent replay: same ticket already posted -> return that result, no new row.
        DECLARE @existingTxId INT, @existingPoints DECIMAL(12,2), @existingBalance DECIMAL(12,2);
        SELECT TOP 1 @existingTxId = transactionId, @existingPoints = points, @existingBalance = balanceAfter
        FROM [dbo].[posRewardTransactions]
        WHERE companyId = @companyId AND referenceType = 'ticket' AND referenceId = @incomeId;

        IF @existingTxId IS NOT NULL
        BEGIN
            SELECT @existingPoints AS pointsEarned, @existingBalance AS newBalance, @existingTxId AS transactionId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            RETURN;
        END

        -- Server-side calculation ONLY: never trust points from the frontend.
        DECLARE @points DECIMAL(12,2) = (
            SELECT SUM(r.pointsPerUnit * d.quantity)
            FROM [dbo].[incomeDetails] d
            JOIN [dbo].[posRewardProductRates] r
                ON r.productId = d.productId AND r.companyId = @companyId AND r.isActive = 1
            WHERE d.incomeId = @incomeId
        );

        IF @points IS NULL OR @points <= 0
        BEGIN
            -- No rated products on this ticket -- nothing to post, but a
            -- successful no-op response (not a 404/500) so the POS never
            -- treats "no configured rate yet" as a failure.
            DECLARE @currentBalance DECIMAL(12,2) = ISNULL(
                (SELECT balance FROM [dbo].[posRewardBalances] WHERE companyId = @companyId AND clientId = @clientId), 0);
            SELECT CAST(0 AS DECIMAL(12,2)) AS pointsEarned, @currentBalance AS newBalance, CAST(NULL AS INT) AS transactionId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            RETURN;
        END

        BEGIN TRAN;

        DECLARE @newBalance DECIMAL(12,2);
        EXEC [dbo].[sp_posRewardBalances_applyDelta]
            @companyId = @companyId, @clientId = @clientId,
            @pointsDelta = @points, @earnedDelta = @points, @redeemedDelta = 0,
            @newBalance = @newBalance OUTPUT;

        INSERT INTO [dbo].[posRewardTransactions]
            (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
        VALUES
            (@companyId, @clientId, 'EARN', 'C', @points, 'ticket', @incomeId, @newBalance, CONCAT('Ticket #', @incomeId));

        DECLARE @transactionId INT = SCOPE_IDENTITY();

        COMMIT TRAN;

        SELECT @points AS pointsEarned, @newBalance AS newBalance, @transactionId AS transactionId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        -- Race: two concurrent retries for the same ticket both pass the
        -- idempotency SELECT before either commits -> UNIQUE violation here
        -- is expected and not a real error; surface it distinctly.
        IF ERROR_NUMBER() IN (2601, 2627) AND @Error LIKE '%UQ_posRewardTransactions_ticket%'
            SELECT ('{"error":"already_posted"}') AS [jsonResult]
        ELSE
            SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardTransactions_adjust — manual admin points adjustment.
-- points may be positive or negative.
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardTransactions_adjust', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardTransactions_adjust;
GO
CREATE PROCEDURE [dbo].[sp_posRewardTransactions_adjust]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].companyId'));
        DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].clientId'));
        DECLARE @points DECIMAL(12,2) = TRY_CONVERT(DECIMAL(12,2), JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].points'));
        DECLARE @description NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].description');
        DECLARE @createdByUserId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardTransactions[0].createdByUserId'));

        IF @companyId IS NULL OR @clientId IS NULL OR @points IS NULL OR @points = 0
            RAISERROR('companyId, clientId y points (distinto de 0) son requeridos.', 16, 1);

        DECLARE @direction NVARCHAR(1) = CASE WHEN @points >= 0 THEN 'C' ELSE 'D' END;
        DECLARE @absPoints DECIMAL(12,2) = ABS(@points);
        -- EXEC's @param = value only accepts a constant or a bare variable,
        -- never an inline expression -- CASE has to be pre-computed here.
        DECLARE @earnedDelta DECIMAL(12,2) = CASE WHEN @points > 0 THEN @points ELSE 0 END;
        DECLARE @redeemedDeltaIn DECIMAL(12,2) = CASE WHEN @points < 0 THEN @absPoints ELSE 0 END;

        BEGIN TRAN;

        DECLARE @newBalance DECIMAL(12,2);
        EXEC [dbo].[sp_posRewardBalances_applyDelta]
            @companyId = @companyId, @clientId = @clientId,
            @pointsDelta = @points,
            @earnedDelta = @earnedDelta,
            @redeemedDelta = @redeemedDeltaIn,
            @newBalance = @newBalance OUTPUT;

        INSERT INTO [dbo].[posRewardTransactions]
            (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
        VALUES
            (@companyId, @clientId, 'ADJUSTMENT', @direction, @absPoints, 'manual', NULL, @newBalance,
             ISNULL(@description, CONCAT('Ajuste manual por usuario ', @createdByUserId)));

        COMMIT TRAN;

        SELECT @newBalance AS newBalance
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardRedemptions — action 0=read only (writes go through
-- sp_posRewardRedemptions_redeem, which is transactional).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardRedemptions', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardRedemptions;
GO
CREATE PROCEDURE [dbo].[sp_posRewardRedemptions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].companyId'));
        DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].clientId'));
        IF @companyId IS NULL RAISERROR('companyId es requerido.', 16, 1);

        DECLARE @redemptionsJson NVARCHAR(MAX) = (
            SELECT redemptionId, companyId, clientId, catalogItemId, pointsSpent, status,
                   incomeId, redeemedByUserId, CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM [dbo].[posRewardRedemptions]
            WHERE companyId = @companyId
              AND (@clientId IS NULL OR clientId = @clientId)
            ORDER BY created_At DESC
            FOR JSON PATH
        );
        SELECT ('{"result":[{"posRewardRedemptions":' + ISNULL(@redemptionsJson, '[]') + '}]}') AS [jsonResult]
    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"result":[{"error":"1","msg":"' + REPLACE(@Error, '"', '\"') + '"}]}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_posRewardRedemptions_redeem — transactional: insufficient balance
-- rolls back and returns {"error":"insufficient_points","balance"} —
-- a valid business outcome, NOT an exception (Python maps it to HTTP 200).
-- ============================================================
IF OBJECT_ID('dbo.sp_posRewardRedemptions_redeem', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardRedemptions_redeem;
GO
CREATE PROCEDURE [dbo].[sp_posRewardRedemptions_redeem]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].companyId'));
        DECLARE @clientId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].clientId'));
        DECLARE @catalogItemId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].catalogItemId'));
        DECLARE @redeemedByUserId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].redeemedByUserId'));
        DECLARE @incomeId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardRedemptions[0].incomeId'));

        IF @companyId IS NULL OR @clientId IS NULL OR @catalogItemId IS NULL OR @redeemedByUserId IS NULL
            RAISERROR('companyId, clientId, catalogItemId y redeemedByUserId son requeridos.', 16, 1);

        DECLARE @requiredPoints DECIMAL(12,2), @rewardType NVARCHAR(30), @freeProductId INT;
        SELECT @requiredPoints = requiredPoints, @rewardType = rewardType, @freeProductId = freeProductId
        FROM [dbo].[posRewardCatalogItems]
        WHERE catalogItemId = @catalogItemId AND companyId = @companyId AND isActive = 1;

        IF @requiredPoints IS NULL
            RAISERROR('La recompensa no existe, no pertenece a esta empresa, o no está activa.', 16, 1);

        -- free_product rewards must be earned from THAT specific product, not
        -- from the client's mixed, fungible points balance -- otherwise 3
        -- cheap purchases across different products could fund one expensive
        -- item's "free" reward. Units purchased/consumed are derived from
        -- real ticket history (incomeDetails), no new tables needed: pointsPerUnit
        -- converts the catalog item's point cost into a physical unit count for
        -- this product, and each prior 'applied' redemption of this exact
        -- catalogItemId is assumed to have consumed that many units.
        IF @rewardType = 'free_product' AND @freeProductId IS NOT NULL
        BEGIN
            DECLARE @pointsPerUnit DECIMAL(12,2) = (
                SELECT pointsPerUnit FROM [dbo].[posRewardProductRates]
                WHERE companyId = @companyId AND productId = @freeProductId AND isActive = 1
            );
            DECLARE @requiredUnits DECIMAL(12,2) = CASE
                WHEN ISNULL(@pointsPerUnit, 0) > 0 THEN @requiredPoints / @pointsPerUnit
                ELSE @requiredPoints
            END;

            DECLARE @unitsPurchased DECIMAL(12,2) = ISNULL((
                SELECT SUM(d.quantity)
                FROM [dbo].[incomeDetails] d
                JOIN [dbo].[income] i ON i.incomeId = d.incomeId
                WHERE d.productId = @freeProductId AND i.clientId = @clientId AND i.companyId = @companyId
            ), 0);

            DECLARE @priorRedemptions INT = (
                SELECT COUNT(*) FROM [dbo].[posRewardRedemptions]
                WHERE companyId = @companyId AND clientId = @clientId
                    AND catalogItemId = @catalogItemId AND status = 'applied'
            );
            DECLARE @unitsAvailable DECIMAL(12,2) = @unitsPurchased - (@priorRedemptions * @requiredUnits);

            IF @unitsAvailable < @requiredUnits
            BEGIN
                SELECT ('{"error":"insufficient_product_units","required":' + CONVERT(NVARCHAR(30), @requiredUnits) +
                    ',"purchased":' + CONVERT(NVARCHAR(30), @unitsPurchased) +
                    ',"available":' + CONVERT(NVARCHAR(30), @unitsAvailable) + '}') AS [jsonResult]
                RETURN;
            END
        END

        DECLARE @currentBalance DECIMAL(12,2) = ISNULL(
            (SELECT balance FROM [dbo].[posRewardBalances] WHERE companyId = @companyId AND clientId = @clientId), 0);

        IF @currentBalance < @requiredPoints
        BEGIN
            SELECT ('{"error":"insufficient_points","balance":' + CONVERT(NVARCHAR(30), @currentBalance) + '}') AS [jsonResult]
            RETURN;
        END

        BEGIN TRAN;

        INSERT INTO [dbo].[posRewardRedemptions]
            (companyId, clientId, catalogItemId, pointsSpent, status, incomeId, redeemedByUserId)
        VALUES
            (@companyId, @clientId, @catalogItemId, @requiredPoints, 'applied', @incomeId, @redeemedByUserId);

        DECLARE @redemptionId INT = SCOPE_IDENTITY();

        -- EXEC's @param = value only accepts a constant or a bare variable,
        -- never an inline expression -- the negation has to be pre-computed here.
        DECLARE @negRequiredPoints DECIMAL(12,2) = -@requiredPoints;
        DECLARE @newBalance DECIMAL(12,2);
        EXEC [dbo].[sp_posRewardBalances_applyDelta]
            @companyId = @companyId, @clientId = @clientId,
            @pointsDelta = @negRequiredPoints, @earnedDelta = 0, @redeemedDelta = @requiredPoints,
            @newBalance = @newBalance OUTPUT;

        INSERT INTO [dbo].[posRewardTransactions]
            (companyId, clientId, txType, direction, points, referenceType, referenceId, balanceAfter, description)
        VALUES
            (@companyId, @clientId, 'REDEEM', 'D', @requiredPoints, 'redemption', @redemptionId, @newBalance,
             CONCAT('Canje #', @redemptionId));

        COMMIT TRAN;

        SELECT 'applied' AS status, @redemptionId AS redemptionId, @requiredPoints AS pointsSpent, @newBalance AS newBalance
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ─────────────────────────────────────────────────────────────────────────────
-- sp_posRewardProductCounts
-- Returns available units per rewardable product for a client.
-- "Available" = total purchased - units consumed by applied redemptions.
-- Used by the stamp-card UI to show accurate per-product progress.
-- Input:  { "posRewardProductCounts": [{ "companyId": int, "clientId": int }] }
-- Output: { "result": [{ "posRewardProductCounts": [{ "productId", "unitsPurchased", "unitsConsumed", "unitsAvailable" }] }] }
-- ─────────────────────────────────────────────────────────────────────────────
IF OBJECT_ID('dbo.sp_posRewardProductCounts', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_posRewardProductCounts;
GO
CREATE PROCEDURE [dbo].[sp_posRewardProductCounts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductCounts[0].companyId'));
        DECLARE @clientId  INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.posRewardProductCounts[0].clientId'));

        IF @companyId IS NULL OR @clientId IS NULL
        BEGIN
            SELECT ('{"error":"companyId and clientId are required"}') AS [jsonResult];
            RETURN;
        END

        -- Units purchased per product
        -- Note: income.companyId is not filtered here — the earn SP also omits it
        -- when summing incomeDetails (see lines 503-508 of sp_posRewardTransactions_earnFromTicket).
        -- We scope to the client and restrict products to those with active rates for this company.
        ;WITH purchased AS (
            SELECT d.productId, SUM(d.quantity) AS unitsPurchased
            FROM [dbo].[incomeDetails] d
            JOIN [dbo].[income] i ON i.incomeId = d.incomeId
            WHERE i.clientId = @clientId
            GROUP BY d.productId
        ),
        -- Units consumed by applied redemptions per catalog item
        consumed AS (
            SELECT c.freeProductId AS productId,
                   COUNT(*) * (c.requiredPoints / ISNULL(r.pointsPerUnit, 1)) AS unitsConsumed
            FROM [dbo].[posRewardRedemptions] rd
            JOIN [dbo].[posRewardCatalogItems] c ON c.catalogItemId = rd.catalogItemId
            LEFT JOIN [dbo].[posRewardProductRates] r
                ON r.companyId = @companyId AND r.productId = c.freeProductId AND r.isActive = 1
            WHERE rd.companyId = @companyId AND rd.clientId = @clientId AND rd.status = 'applied'
              AND c.rewardType = 'free_product' AND c.freeProductId IS NOT NULL
            GROUP BY c.freeProductId, c.requiredPoints, r.pointsPerUnit
        )
        SELECT (
            SELECT
                p.productId,
                p.unitsPurchased,
                ISNULL(con.unitsConsumed, 0) AS unitsConsumed,
                p.unitsPurchased - ISNULL(con.unitsConsumed, 0) AS unitsAvailable
            FROM purchased p
            JOIN [dbo].[posRewardProductRates] pr
                ON pr.companyId = @companyId AND pr.productId = p.productId AND pr.isActive = 1
            LEFT JOIN consumed con ON con.productId = p.productId
            FOR JSON PATH, ROOT('posRewardProductCounts')
        ) AS [jsonResult];

    END TRY
    BEGIN CATCH
        DECLARE @Error NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Error, '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
