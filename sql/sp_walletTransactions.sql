-- ============================================================
-- sp_walletTransactions — INSERT-ONLY immutable money ledger.
-- Balances are projections over this table; corrections are new
-- REVERSAL entries, never UPDATE/DELETE (actions 2/3 are rejected).
-- Banking-first Phase 1 (docs/payment-banking-first-redesign.md).
-- Spec: posgmo-factory/tests/prd_walletTransaction.json
-- ============================================================

-- ── Table: walletTransactions_entryType (lookup / catalog) ──
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'walletTransactions_entryType')
CREATE TABLE [dbo].[walletTransactions_entryType] (
    entryType    NVARCHAR(30)   NOT NULL PRIMARY KEY,
    sortOrder    INT            NOT NULL,
    description  NVARCHAR(100)  NULL
)
GO

MERGE [dbo].[walletTransactions_entryType] AS t
USING (VALUES
    ('DEPOSIT',                1, 'Money in (SPEI a CLABE virtual / top-up)'),
    ('RESERVE',                2, 'Funds locked for a pending loan funding'),
    ('RELEASE',                3, 'Reserved funds unlocked (funding failed/cancelled)'),
    ('LOAN_FUNDING',           4, 'Lender funds a loan (out)'),
    ('DISBURSEMENT_RECEIVED',  5, 'Borrower receives loan principal'),
    ('REPAYMENT_PRINCIPAL',    6, 'Installment principal received'),
    ('REPAYMENT_INTEREST',     7, 'Installment interest received'),
    ('PLATFORM_FEE',           8, 'SmartLoans commission'),
    ('WITHDRAWAL',             9, 'Payout to bank account (out)'),
    ('REFUND',                10, 'Money returned to the client'),
    ('REVERSAL',              11, 'Correction of a previous entry'),
    ('ADJUSTMENT',            12, 'Manual admin adjustment')
) AS s (entryType, sortOrder, description)
ON t.entryType = s.entryType
WHEN NOT MATCHED THEN
    INSERT (entryType, sortOrder, description) VALUES (s.entryType, s.sortOrder, s.description);
GO

-- ── Table: walletTransactions ───────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'walletTransactions')
CREATE TABLE [dbo].[walletTransactions] (
    entryId         BIGINT IDENTITY PRIMARY KEY,
    companyId       INT            NOT NULL,
    clientId        INT            NULL,       -- NULL = platform's own ledger
    entryType       NVARCHAR(30)   NOT NULL,
    direction       CHAR(1)        NOT NULL,   -- D | C (wallet owner's perspective)
    amountMXN       DECIMAL(12,2)  NOT NULL,   -- always positive; direction carries the sign
    referenceType   NVARCHAR(20)   NULL,       -- transfer | collection | loan | stripe_tx | manual
    referenceId     INT            NULL,
    idempotencyKey  NVARCHAR(64)   NOT NULL,
    balanceAfter    DECIMAL(12,2)  NULL,       -- running available balance, set by the SP
    note            NVARCHAR(255)  NULL,
    created_At      DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT CK_walletTransactions_direction CHECK (direction IN ('D','C')),
    CONSTRAINT CK_walletTransactions_amount    CHECK (amountMXN > 0)
)
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_walletTransactions_entryType')
    ALTER TABLE [dbo].[walletTransactions]
        ADD CONSTRAINT FK_walletTransactions_entryType
        FOREIGN KEY (entryType) REFERENCES [dbo].[walletTransactions_entryType] (entryType);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_walletTransactions_idem')
    CREATE UNIQUE INDEX UQ_walletTransactions_idem
        ON [dbo].[walletTransactions] (companyId, idempotencyKey);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_walletTransactions_client')
    CREATE INDEX IX_walletTransactions_client
        ON [dbo].[walletTransactions] (companyId, clientId, entryId DESC);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_walletTransactions_reference')
    CREATE INDEX IX_walletTransactions_reference
        ON [dbo].[walletTransactions] (referenceType, referenceId);
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_walletTransactions', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_walletTransactions;
GO

CREATE PROCEDURE [dbo].[sp_walletTransactions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         INT            = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].action')
        DECLARE @companyId      INT            = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].companyId')
        DECLARE @clientId       INT            = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].clientId')
        DECLARE @entryType      NVARCHAR(30)   = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].entryType')
        DECLARE @direction      CHAR(1)        = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].direction')
        DECLARE @amountMXN      DECIMAL(12,2)  = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].amountMXN')
        DECLARE @referenceType  NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].referenceType')
        DECLARE @referenceId    INT            = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].referenceId')
        DECLARE @idempotencyKey NVARCHAR(64)   = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].idempotencyKey')
        DECLARE @note           NVARCHAR(255)  = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].note')

        IF @action = 1 -- INSERT (the only mutation this ledger allows)
        BEGIN
            -- Idempotent replay: same key returns the original entry, no double post.
            IF EXISTS (SELECT 1 FROM [dbo].[walletTransactions]
                       WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey)
            BEGIN
                SELECT (SELECT TOP 1 entryId, companyId, clientId, entryType, direction,
                               amountMXN, balanceAfter, idempotencyKey, note,
                               'true' AS replayed,
                               CONVERT(NVARCHAR, created_At, 127) AS created_At
                        FROM [dbo].[walletTransactions]
                        WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
                RETURN
            END

            BEGIN TRANSACTION;

            -- Serialize per wallet: HOLDLOCK on the owner's tail entry so two
            -- concurrent inserts can't both read the same previous balance.
            DECLARE @prev DECIMAL(12,2) = ISNULL(
                (SELECT TOP 1 balanceAfter
                 FROM [dbo].[walletTransactions] WITH (UPDLOCK, HOLDLOCK)
                 WHERE companyId = @companyId
                   AND ((@clientId IS NULL AND clientId IS NULL) OR clientId = @clientId)
                 ORDER BY entryId DESC), 0);

            DECLARE @newBalance DECIMAL(12,2) =
                @prev + CASE @direction WHEN 'C' THEN @amountMXN ELSE -@amountMXN END;

            -- Debits cannot overdraw the wallet (RESERVE/RELEASE included:
            -- available balance is what this running figure represents).
            IF @newBalance < 0
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT '{"error":"Saldo insuficiente","available":' + CAST(@prev AS NVARCHAR(20)) + '}' AS [jsonResult]
                RETURN
            END

            INSERT INTO [dbo].[walletTransactions]
                (companyId, clientId, entryType, direction, amountMXN,
                 referenceType, referenceId, idempotencyKey, balanceAfter, note)
            VALUES
                (@companyId, @clientId, @entryType, @direction, @amountMXN,
                 @referenceType, @referenceId, @idempotencyKey, @newBalance, @note)

            COMMIT TRANSACTION;

            SELECT (SELECT TOP 1 entryId, companyId, clientId, entryType, direction,
                           amountMXN, balanceAfter, idempotencyKey, note,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[walletTransactions]
                    WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
        ELSE
            -- INSERT-only ledger: no updates, no deletes — ever.
            SELECT '{"error":"walletTransactions es un ledger INSERT-only; las correcciones son asientos REVERSAL (action 1)."}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_walletTransactions_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_walletTransactions_all;
GO
CREATE PROCEDURE [dbo].[sp_walletTransactions_all]  -- statement / movements view
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT           = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].companyId')
    DECLARE @clientId  INT           = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].clientId')
    DECLARE @entryType NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].entryType')

    SELECT ISNULL(
        (SELECT TOP 200 entryId, companyId, clientId, entryType, direction, amountMXN,
                referenceType, referenceId, balanceAfter, note,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[walletTransactions]
         WHERE companyId = @companyId
           AND ((@clientId IS NULL AND clientId IS NULL) OR clientId = @clientId)
           AND (@entryType IS NULL OR entryType = @entryType)
         ORDER BY entryId DESC
         FOR JSON PATH, ROOT('walletTransactions')),
        '{"walletTransactions":[]}'
    ) AS [jsonResult]
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_walletTransactions_balance', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_walletTransactions_balance;
GO
CREATE PROCEDURE [dbo].[sp_walletTransactions_balance]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].companyId')
    DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.walletTransactions[0].clientId')

    -- available = running balance (tail entry). reserved = RESERVE minus RELEASE
    -- (already subtracted from available; shown separately for the UI).
    DECLARE @available DECIMAL(12,2) = ISNULL(
        (SELECT TOP 1 balanceAfter FROM [dbo].[walletTransactions]
         WHERE companyId = @companyId
           AND ((@clientId IS NULL AND clientId IS NULL) OR clientId = @clientId)
         ORDER BY entryId DESC), 0);

    DECLARE @reserved DECIMAL(12,2) = ISNULL(
        (SELECT SUM(CASE entryType WHEN 'RESERVE' THEN amountMXN
                                   WHEN 'RELEASE' THEN -amountMXN ELSE 0 END)
         FROM [dbo].[walletTransactions]
         WHERE companyId = @companyId
           AND ((@clientId IS NULL AND clientId IS NULL) OR clientId = @clientId)
           AND entryType IN ('RESERVE','RELEASE')), 0);
    IF @reserved < 0 SET @reserved = 0;

    SELECT ('{"availableBalance":' + CAST(@available AS NVARCHAR(20)) +
            ',"reservedBalance":'  + CAST(@reserved  AS NVARCHAR(20)) + '}') AS [jsonResult]
END
GO
