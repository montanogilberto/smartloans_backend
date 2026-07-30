-- ============================================================
-- sp_transfers  (action 1=create, 2=update status; NO delete —
-- transfers are audit records of money that moved).
-- Outbound SPEI dispersión: loan disbursements, lender payouts,
-- refunds. Banking-first Phase 1 (docs/payment-banking-first-redesign.md).
-- Spec: posgmo-factory/tests/prd_transfer.json
-- ============================================================

-- ── Table: transfers_status (lookup / catalog) ──────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'transfers_status')
CREATE TABLE [dbo].[transfers_status] (
    statusCode   NVARCHAR(20)   NOT NULL PRIMARY KEY,
    sortOrder    INT            NOT NULL,
    description  NVARCHAR(100)  NULL,
    isTerminal   BIT            NOT NULL DEFAULT 0
)
GO

MERGE [dbo].[transfers_status] AS t
USING (VALUES
    ('pending',  1, 'Created, not yet sent to the provider', 0),
    ('sent',     2, 'Accepted by the provider, in SPEI',     0),
    ('settled',  3, 'Settled — CEP available',               1),
    ('returned', 4, 'Returned by the receiving bank',        1),
    ('failed',   5, 'Provider rejected the transfer',        1)
) AS s (statusCode, sortOrder, description, isTerminal)
ON t.statusCode = s.statusCode
WHEN NOT MATCHED THEN
    INSERT (statusCode, sortOrder, description, isTerminal)
    VALUES (s.statusCode, s.sortOrder, s.description, s.isTerminal);
GO

-- ── Table: transfers ────────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'transfers')
CREATE TABLE [dbo].[transfers] (
    transferId       INT IDENTITY PRIMARY KEY,
    companyId        INT            NOT NULL,
    toClientId       INT            NOT NULL,
    toBankAccountId  INT            NOT NULL,
    amountMXN        DECIMAL(12,2)  NOT NULL,
    purpose          NVARCHAR(30)   NOT NULL,  -- loan_disbursement | lender_payout | refund
    loanId           INT            NULL,
    provider         NVARCHAR(20)   NOT NULL DEFAULT 'stp',  -- stp | stripe
    providerRef      NVARCHAR(100)  NULL,      -- STP claveRastreo / Stripe transfer id
    cepUrl           NVARCHAR(2048) NULL,      -- Banxico CEP receipt
    status           NVARCHAR(20)   NOT NULL DEFAULT 'pending',
    failureReason    NVARCHAR(500)  NULL,
    idempotencyKey   NVARCHAR(64)   NOT NULL,
    settledAt        DATETIME2      NULL,
    created_At       DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at       DATETIME2      NULL,
    CONSTRAINT CK_transfers_amount CHECK (amountMXN > 0)
)
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_transfers_status')
    ALTER TABLE [dbo].[transfers]
        ADD CONSTRAINT FK_transfers_status
        FOREIGN KEY (status) REFERENCES [dbo].[transfers_status] (statusCode);
GO
IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_transfers_bankAccount')
    ALTER TABLE [dbo].[transfers]
        ADD CONSTRAINT FK_transfers_bankAccount
        FOREIGN KEY (toBankAccountId) REFERENCES [dbo].[bankAccounts] (bankAccountId);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_transfers_idem')
    CREATE UNIQUE INDEX UQ_transfers_idem
        ON [dbo].[transfers] (companyId, idempotencyKey);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_transfers_company_client')
    CREATE INDEX IX_transfers_company_client
        ON [dbo].[transfers] (companyId, toClientId, created_At DESC);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_transfers_status')
    CREATE INDEX IX_transfers_status
        ON [dbo].[transfers] (status) INCLUDE (companyId, created_At);
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_transfers', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_transfers;
GO

CREATE PROCEDURE [dbo].[sp_transfers]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action          INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].action')
        DECLARE @transferId      INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].transferId')
        DECLARE @companyId       INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].companyId')
        DECLARE @toClientId      INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].toClientId')
        DECLARE @toBankAccountId INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].toBankAccountId')
        DECLARE @amountMXN       DECIMAL(12,2)  = JSON_VALUE(@pjsonfile, '$.transfers[0].amountMXN')
        DECLARE @purpose         NVARCHAR(30)   = JSON_VALUE(@pjsonfile, '$.transfers[0].purpose')
        DECLARE @loanId          INT            = JSON_VALUE(@pjsonfile, '$.transfers[0].loanId')
        DECLARE @provider        NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.transfers[0].provider')
        DECLARE @providerRef     NVARCHAR(100)  = JSON_VALUE(@pjsonfile, '$.transfers[0].providerRef')
        DECLARE @cepUrl          NVARCHAR(2048) = JSON_VALUE(@pjsonfile, '$.transfers[0].cepUrl')
        DECLARE @status          NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.transfers[0].status')
        DECLARE @failureReason   NVARCHAR(500)  = JSON_VALUE(@pjsonfile, '$.transfers[0].failureReason')
        DECLARE @idempotencyKey  NVARCHAR(64)   = JSON_VALUE(@pjsonfile, '$.transfers[0].idempotencyKey')

        IF @action = 1 -- CREATE (idempotent: same key returns the original)
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[transfers]
                       WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey)
            BEGIN
                SELECT (SELECT TOP 1 transferId, toClientId, amountMXN, purpose, provider,
                               providerRef, cepUrl, status, 'true' AS replayed,
                               CONVERT(NVARCHAR, created_At, 127) AS created_At
                        FROM [dbo].[transfers]
                        WHERE companyId = @companyId AND idempotencyKey = @idempotencyKey
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
                RETURN
            END

            INSERT INTO [dbo].[transfers]
                (companyId, toClientId, toBankAccountId, amountMXN, purpose, loanId,
                 provider, idempotencyKey, status)
            VALUES
                (@companyId, @toClientId, @toBankAccountId, @amountMXN, @purpose, @loanId,
                 ISNULL(@provider, 'stp'), @idempotencyKey, 'pending')

            SELECT (SELECT TOP 1 transferId, companyId, toClientId, toBankAccountId,
                           amountMXN, purpose, provider, status, idempotencyKey,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[transfers]
                    WHERE transferId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (provider result / webhook advance)
        BEGIN
            UPDATE [dbo].[transfers]
            SET status        = ISNULL(@status, status),
                providerRef   = ISNULL(@providerRef, providerRef),
                cepUrl        = ISNULL(@cepUrl, cepUrl),
                failureReason = ISNULL(@failureReason, failureReason),
                settledAt     = CASE WHEN @status = 'settled' THEN GETUTCDATE() ELSE settledAt END,
                updated_at    = GETUTCDATE()
            WHERE transferId = @transferId AND companyId = @companyId

            SELECT (SELECT TOP 1 transferId, toClientId, amountMXN, purpose, provider,
                           providerRef, cepUrl, status, failureReason,
                           CONVERT(NVARCHAR, settledAt, 127) AS settledAt
                    FROM [dbo].[transfers]
                    WHERE transferId = @transferId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE
            -- No action 3: money-movement records are never deleted.
            SELECT '{"error":"Transfers son registros de auditoría — sin delete. Acciones válidas: 1 crear, 2 actualizar."}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_transfers_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_transfers_all;
GO
CREATE PROCEDURE [dbo].[sp_transfers_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId  INT           = JSON_VALUE(@pjsonfile, '$.transfers[0].companyId')
    DECLARE @toClientId INT           = JSON_VALUE(@pjsonfile, '$.transfers[0].toClientId')
    DECLARE @status     NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.transfers[0].status')
    DECLARE @purpose    NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.transfers[0].purpose')

    SELECT ISNULL(
        (SELECT TOP 200 transferId, companyId, toClientId, toBankAccountId, amountMXN,
                purpose, loanId, provider, providerRef, cepUrl, status, failureReason,
                CONVERT(NVARCHAR, settledAt, 127)  AS settledAt,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[transfers]
         WHERE companyId = @companyId
           AND (@toClientId IS NULL OR toClientId = @toClientId)
           AND (@status     IS NULL OR status     = @status)
           AND (@purpose    IS NULL OR purpose    = @purpose)
         ORDER BY created_At DESC
         FOR JSON PATH, ROOT('transfers')),
        '{"transfers":[]}'
    ) AS [jsonResult]
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_transfers_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_transfers_one;
GO
CREATE PROCEDURE [dbo].[sp_transfers_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId      INT          = JSON_VALUE(@pjsonfile, '$.transfers[0].companyId')
    DECLARE @transferId     INT          = JSON_VALUE(@pjsonfile, '$.transfers[0].transferId')
    DECLARE @idempotencyKey NVARCHAR(64) = JSON_VALUE(@pjsonfile, '$.transfers[0].idempotencyKey')

    SELECT ISNULL(
        (SELECT TOP 1 transferId, companyId, toClientId, toBankAccountId, amountMXN,
                purpose, loanId, provider, providerRef, cepUrl, status, failureReason,
                idempotencyKey,
                CONVERT(NVARCHAR, settledAt, 127)  AS settledAt,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[transfers]
         WHERE (@transferId IS NOT NULL AND transferId = @transferId)
            OR (@idempotencyKey IS NOT NULL AND companyId = @companyId AND idempotencyKey = @idempotencyKey)
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        '{}'
    ) AS [jsonResult]
END
GO
