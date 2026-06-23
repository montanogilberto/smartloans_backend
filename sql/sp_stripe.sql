-- ============================================================
-- Stripe tables + stored procedures
-- Run this script once in your Azure SQL database
-- ============================================================

-- ── Table: stripeConnectedAccounts ─────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'stripeConnectedAccounts')
CREATE TABLE [dbo].[stripeConnectedAccounts] (
    id                  INT IDENTITY PRIMARY KEY,
    clientId            INT NOT NULL,
    companyId           INT NOT NULL,
    connectedAccountId  NVARCHAR(100) NOT NULL,   -- Stripe acct_xxx
    chargesEnabled      BIT NOT NULL DEFAULT 0,
    payoutsEnabled      BIT NOT NULL DEFAULT 0,
    detailsSubmitted    BIT NOT NULL DEFAULT 0,
    created_At          DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at          DATETIME2 NULL,
    CONSTRAINT UQ_stripeAccounts_client UNIQUE (clientId, companyId)
)
GO

-- ── Table: stripeTransactions ───────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'stripeTransactions')
CREATE TABLE [dbo].[stripeTransactions] (
    transactionId           INT IDENTITY PRIMARY KEY,
    companyId               INT NOT NULL,
    loanId                  INT NULL,
    proposalId              INT NULL,
    fromClientId            INT NOT NULL,
    toClientId              INT NOT NULL,
    amount                  INT NOT NULL,            -- centavos MXN
    currency                NVARCHAR(3) NOT NULL DEFAULT 'mxn',
    paymentType             NVARCHAR(30) NOT NULL,
    -- wallet_top_up | loan_disbursement | loan_repayment | wallet_withdrawal
    status                  NVARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending | processing | succeeded | failed | refunded | requires_action
    stripePaymentIntentId   NVARCHAR(100) NULL,
    stripeTransferId        NVARCHAR(100) NULL,
    failureReason           NVARCHAR(500) NULL,
    created_At              DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at              DATETIME2 NULL,
)
GO

-- ============================================================
-- sp_stripe_connectedAccounts  (action = 'upsert' | 'get')
-- ============================================================
IF OBJECT_ID('dbo.sp_stripe_connectedAccounts', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_stripe_connectedAccounts;
GO

CREATE PROCEDURE [dbo].[sp_stripe_connectedAccounts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action             NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].action')
        DECLARE @clientId           INT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].clientId')
        DECLARE @companyId          INT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].companyId')
        DECLARE @connectedAccountId NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].connectedAccountId')
        DECLARE @chargesEnabled     BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].chargesEnabled')
        DECLARE @payoutsEnabled     BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].payoutsEnabled')
        DECLARE @detailsSubmitted   BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].detailsSubmitted')

        IF @action = 'upsert'
        BEGIN
            MERGE [dbo].[stripeConnectedAccounts] AS target
            USING (SELECT @clientId AS clientId, @companyId AS companyId) AS source
                ON target.clientId = source.clientId AND target.companyId = source.companyId
            WHEN MATCHED THEN
                UPDATE SET connectedAccountId = ISNULL(@connectedAccountId, target.connectedAccountId),
                           chargesEnabled     = ISNULL(@chargesEnabled,     target.chargesEnabled),
                           payoutsEnabled     = ISNULL(@payoutsEnabled,     target.payoutsEnabled),
                           detailsSubmitted   = ISNULL(@detailsSubmitted,   target.detailsSubmitted),
                           updated_at         = GETUTCDATE()
            WHEN NOT MATCHED THEN
                INSERT (clientId, companyId, connectedAccountId, chargesEnabled, payoutsEnabled, detailsSubmitted)
                VALUES (@clientId, @companyId, @connectedAccountId,
                        ISNULL(@chargesEnabled, 0), ISNULL(@payoutsEnabled, 0), ISNULL(@detailsSubmitted, 0));

            SELECT (SELECT TOP 1 * FROM [dbo].[stripeConnectedAccounts]
                    WHERE clientId = @clientId AND companyId = @companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 connectedAccountId, clientId, companyId,
                        chargesEnabled, payoutsEnabled, detailsSubmitted,
                        CONVERT(NVARCHAR, created_At, 127) AS created_At
                 FROM [dbo].[stripeConnectedAccounts]
                 WHERE clientId = @clientId AND companyId = @companyId
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
-- sp_stripe_transactions  (action = 'insert' | 'update_status' | 'list')
-- ============================================================
IF OBJECT_ID('dbo.sp_stripe_transactions', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_stripe_transactions;
GO

CREATE PROCEDURE [dbo].[sp_stripe_transactions]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action                 NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].action')
        DECLARE @companyId              INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].companyId')
        DECLARE @loanId                 INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].loanId')
        DECLARE @proposalId             INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].proposalId')
        DECLARE @fromClientId           INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].fromClientId')
        DECLARE @toClientId             INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].toClientId')
        DECLARE @amount                 INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].amount')
        DECLARE @currency               NVARCHAR(3)   = ISNULL(JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].currency'), 'mxn')
        DECLARE @paymentType            NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].paymentType')
        DECLARE @status                 NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].status'), 'pending')
        DECLARE @stripePaymentIntentId  NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].stripePaymentIntentId')
        DECLARE @stripeTransferId       NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].stripeTransferId')
        DECLARE @failureReason          NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].failureReason')
        DECLARE @clientId               INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].clientId')

        IF @action = 'insert'
        BEGIN
            INSERT INTO [dbo].[stripeTransactions]
                (companyId, loanId, proposalId, fromClientId, toClientId, amount, currency,
                 paymentType, status, stripePaymentIntentId, stripeTransferId, failureReason)
            VALUES
                (@companyId, @loanId, @proposalId, @fromClientId, @toClientId, @amount, @currency,
                 @paymentType, @status, @stripePaymentIntentId, @stripeTransferId, @failureReason)

            SELECT (SELECT transactionId, status, stripePaymentIntentId, amount, currency
                    FROM [dbo].[stripeTransactions]
                    WHERE transactionId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'update_status'
        BEGIN
            UPDATE [dbo].[stripeTransactions]
            SET status        = @status,
                failureReason = ISNULL(@failureReason, failureReason),
                updated_at    = GETUTCDATE()
            WHERE stripePaymentIntentId = @stripePaymentIntentId
              AND (@companyId IS NULL OR companyId = @companyId)

            SELECT (SELECT TOP 1 transactionId, status, stripePaymentIntentId, amount, currency
                    FROM [dbo].[stripeTransactions]
                    WHERE stripePaymentIntentId = @stripePaymentIntentId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT transactionId, companyId, loanId, proposalId,
                        fromClientId, toClientId, amount, currency,
                        paymentType, status,
                        stripePaymentIntentId, stripeTransferId, failureReason,
                        CONVERT(NVARCHAR, created_At, 127) AS created_At,
                        CONVERT(NVARCHAR, updated_at, 127) AS updated_at
                 FROM [dbo].[stripeTransactions]
                 WHERE companyId = @companyId
                   AND (@clientId    IS NULL OR (fromClientId = @clientId OR toClientId = @clientId))
                   AND (@loanId      IS NULL OR loanId      = @loanId)
                   AND (@paymentType IS NULL OR paymentType = @paymentType)
                 ORDER BY created_At DESC
                 FOR JSON PATH, ROOT('transactions')),
                '{"transactions":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
