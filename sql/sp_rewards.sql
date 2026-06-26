-- ============================================================
-- Rewards & Loyalty Points
-- Tables: rewardRules, rewardPoints, rewardTransactions
-- SP:     sp_rewards
-- Actions: upsert_rule | delete_rule | list_rules
--          earn | redeem | get_balance | list_transactions
-- ============================================================

-- ── Tables ──────────────────────────────────────────────────

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'rewardRules')
CREATE TABLE [dbo].[rewardRules] (
    ruleId          INT IDENTITY PRIMARY KEY,
    companyId       INT NOT NULL,
    ruleName        NVARCHAR(120) NOT NULL,
    ruleType        NVARCHAR(40)  NOT NULL DEFAULT 'purchase', -- purchase | service | manual
    pointsPerUnit   DECIMAL(10,4) NOT NULL DEFAULT 1.0,        -- points per $1 MXN or per service unit
    minAmount       DECIMAL(10,2) NULL,                        -- minimum purchase to earn
    maxPointsPerTx  INT NULL,                                  -- cap per transaction
    isActive        BIT NOT NULL DEFAULT 1,
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2 NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'rewardPoints')
CREATE TABLE [dbo].[rewardPoints] (
    pointId         INT IDENTITY PRIMARY KEY,
    companyId       INT NOT NULL,
    clientId        INT NOT NULL,
    balance         INT NOT NULL DEFAULT 0,
    lifetimeEarned  INT NOT NULL DEFAULT 0,
    lifetimeRedeemed INT NOT NULL DEFAULT 0,
    lastActivity    DATETIME2 NULL,
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2 NULL,
    CONSTRAINT UQ_rewardPoints_client UNIQUE (companyId, clientId)
)
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'rewardTransactions')
CREATE TABLE [dbo].[rewardTransactions] (
    txId            INT IDENTITY PRIMARY KEY,
    companyId       INT NOT NULL,
    clientId        INT NOT NULL,
    ruleId          INT NULL,
    txType          NVARCHAR(20) NOT NULL,  -- earn | redeem | adjustment | expire
    points          INT NOT NULL,
    balanceAfter    INT NOT NULL,
    referenceId     NVARCHAR(100) NULL,     -- sale ID, order ID, etc.
    description     NVARCHAR(255) NULL,
    createdBy       INT NULL,               -- userId who triggered it
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE()
)
GO

-- ── Stored Procedure ─────────────────────────────────────────

IF OBJECT_ID('dbo.sp_rewards', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_rewards;
GO

CREATE PROCEDURE [dbo].[sp_rewards]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        DECLARE @action      NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.rewards[0].action')
        DECLARE @companyId   INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].companyId')
        DECLARE @clientId    INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].clientId')
        DECLARE @ruleId      INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].ruleId')
        DECLARE @createdBy   INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].createdBy')

        -- ── upsert_rule ──────────────────────────────────────
        IF @action = 'upsert_rule'
        BEGIN
            DECLARE @ruleName       NVARCHAR(120) = JSON_VALUE(@pjsonfile, '$.rewards[0].ruleName')
            DECLARE @ruleType       NVARCHAR(40)  = ISNULL(JSON_VALUE(@pjsonfile, '$.rewards[0].ruleType'), 'purchase')
            DECLARE @pointsPerUnit  DECIMAL(10,4) = ISNULL(JSON_VALUE(@pjsonfile, '$.rewards[0].pointsPerUnit'), 1)
            DECLARE @minAmount      DECIMAL(10,2) = JSON_VALUE(@pjsonfile, '$.rewards[0].minAmount')
            DECLARE @maxPointsTx    INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].maxPointsPerTx')
            DECLARE @isActive       BIT           = ISNULL(JSON_VALUE(@pjsonfile, '$.rewards[0].isActive'), 1)

            IF @ruleId IS NOT NULL AND EXISTS (SELECT 1 FROM rewardRules WHERE ruleId = @ruleId AND companyId = @companyId)
            BEGIN
                UPDATE rewardRules SET
                    ruleName       = @ruleName,
                    ruleType       = @ruleType,
                    pointsPerUnit  = @pointsPerUnit,
                    minAmount      = @minAmount,
                    maxPointsPerTx = @maxPointsTx,
                    isActive       = @isActive,
                    updated_at     = GETUTCDATE()
                WHERE ruleId = @ruleId AND companyId = @companyId

                SELECT (SELECT ruleId, companyId, ruleName, ruleType, pointsPerUnit,
                    minAmount, maxPointsPerTx, isActive, created_At, updated_at
                    FROM rewardRules WHERE ruleId = @ruleId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
            END
            ELSE
            BEGIN
                INSERT INTO rewardRules (companyId, ruleName, ruleType, pointsPerUnit, minAmount, maxPointsPerTx, isActive)
                VALUES (@companyId, @ruleName, @ruleType, @pointsPerUnit, @minAmount, @maxPointsTx, @isActive)

                DECLARE @newRuleId INT = SCOPE_IDENTITY()
                SELECT (SELECT ruleId, companyId, ruleName, ruleType, pointsPerUnit,
                    minAmount, maxPointsPerTx, isActive, created_At
                    FROM rewardRules WHERE ruleId = @newRuleId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
            END
        END

        -- ── delete_rule ──────────────────────────────────────
        ELSE IF @action = 'delete_rule'
        BEGIN
            UPDATE rewardRules SET isActive = 0, updated_at = GETUTCDATE()
            WHERE ruleId = @ruleId AND companyId = @companyId
            SELECT '{"deleted":true}' AS [jsonResult]
        END

        -- ── list_rules ───────────────────────────────────────
        ELSE IF @action = 'list_rules'
        BEGIN
            SELECT ISNULL(
                (SELECT ruleId, companyId, ruleName, ruleType, pointsPerUnit,
                    minAmount, maxPointsPerTx, isActive, created_At, updated_at
                    FROM rewardRules
                    WHERE companyId = @companyId AND isActive = 1
                    ORDER BY ruleId
                    FOR JSON PATH),
                '[]'
            ) AS [jsonResult]
        END

        -- ── earn ─────────────────────────────────────────────
        ELSE IF @action = 'earn'
        BEGIN
            DECLARE @earnPoints     INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].points')
            DECLARE @referenceId    NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.rewards[0].referenceId')
            DECLARE @description    NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.rewards[0].description')

            -- Ensure wallet row exists
            IF NOT EXISTS (SELECT 1 FROM rewardPoints WHERE companyId = @companyId AND clientId = @clientId)
                INSERT INTO rewardPoints (companyId, clientId, balance, lifetimeEarned, lifetimeRedeemed)
                VALUES (@companyId, @clientId, 0, 0, 0)

            UPDATE rewardPoints SET
                balance         = balance + @earnPoints,
                lifetimeEarned  = lifetimeEarned + @earnPoints,
                lastActivity    = GETUTCDATE(),
                updated_at      = GETUTCDATE()
            WHERE companyId = @companyId AND clientId = @clientId

            DECLARE @balanceAfterEarn INT
            SELECT @balanceAfterEarn = balance FROM rewardPoints WHERE companyId = @companyId AND clientId = @clientId

            INSERT INTO rewardTransactions (companyId, clientId, ruleId, txType, points, balanceAfter, referenceId, description, createdBy)
            VALUES (@companyId, @clientId, @ruleId, 'earn', @earnPoints, @balanceAfterEarn, @referenceId, @description, @createdBy)

            SELECT (SELECT @balanceAfterEarn AS balance, @earnPoints AS pointsEarned,
                SCOPE_IDENTITY() AS txId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        -- ── redeem ────────────────────────────────────────────
        ELSE IF @action = 'redeem'
        BEGIN
            DECLARE @redeemPoints   INT           = JSON_VALUE(@pjsonfile, '$.rewards[0].points')
            DECLARE @refIdRedeem    NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.rewards[0].referenceId')
            DECLARE @descRedeem     NVARCHAR(255) = JSON_VALUE(@pjsonfile, '$.rewards[0].description')

            DECLARE @currentBalance INT
            SELECT @currentBalance = ISNULL(balance, 0)
            FROM rewardPoints WHERE companyId = @companyId AND clientId = @clientId

            IF @currentBalance < @redeemPoints
            BEGIN
                SELECT '{"error":"insufficient_points","balance":' + CAST(@currentBalance AS NVARCHAR) + '}' AS [jsonResult]
                RETURN
            END

            UPDATE rewardPoints SET
                balance           = balance - @redeemPoints,
                lifetimeRedeemed  = lifetimeRedeemed + @redeemPoints,
                lastActivity      = GETUTCDATE(),
                updated_at        = GETUTCDATE()
            WHERE companyId = @companyId AND clientId = @clientId

            DECLARE @balanceAfterRedeem INT
            SELECT @balanceAfterRedeem = balance FROM rewardPoints WHERE companyId = @companyId AND clientId = @clientId

            INSERT INTO rewardTransactions (companyId, clientId, ruleId, txType, points, balanceAfter, referenceId, description, createdBy)
            VALUES (@companyId, @clientId, NULL, 'redeem', -@redeemPoints, @balanceAfterRedeem, @refIdRedeem, @descRedeem, @createdBy)

            SELECT (SELECT @balanceAfterRedeem AS balance, @redeemPoints AS pointsRedeemed,
                SCOPE_IDENTITY() AS txId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        -- ── get_balance ───────────────────────────────────────
        ELSE IF @action = 'get_balance'
        BEGIN
            SELECT ISNULL(
                (SELECT balance, lifetimeEarned, lifetimeRedeemed, lastActivity, clientId, companyId
                    FROM rewardPoints
                    WHERE companyId = @companyId AND clientId = @clientId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                '{"balance":0,"lifetimeEarned":0,"lifetimeRedeemed":0}'
            ) AS [jsonResult]
        END

        -- ── list_transactions ─────────────────────────────────
        ELSE IF @action = 'list_transactions'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 50 txId, companyId, clientId, ruleId, txType, points, balanceAfter,
                    referenceId, description, createdBy, created_At
                    FROM rewardTransactions
                    WHERE companyId = @companyId
                      AND (@clientId IS NULL OR clientId = @clientId)
                    ORDER BY txId DESC
                    FOR JSON PATH),
                '[]'
            ) AS [jsonResult]
        END

        -- ── list_balances (all clients in company) ────────────
        ELSE IF @action = 'list_balances'
        BEGIN
            SELECT ISNULL(
                (SELECT rp.clientId, rp.balance, rp.lifetimeEarned, rp.lifetimeRedeemed, rp.lastActivity
                    FROM rewardPoints rp
                    WHERE rp.companyId = @companyId
                    ORDER BY rp.balance DESC
                    FOR JSON PATH),
                '[]'
            ) AS [jsonResult]
        END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
