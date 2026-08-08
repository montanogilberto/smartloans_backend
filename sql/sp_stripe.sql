-- ============================================================
-- Stripe tables + stored procedures
-- Run this script once in your Azure SQL database
-- ============================================================

-- ── Table: stripeConnectedAccounts ─────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'stripeConnectedAccounts')
CREATE TABLE [dbo].[stripeConnectedAccounts] (
    id                       INT IDENTITY PRIMARY KEY,
    clientId                 INT NOT NULL,
    companyId                INT NOT NULL,
    connectedAccountId       NVARCHAR(100) NOT NULL,   -- Stripe acct_xxx
    chargesEnabled           BIT NOT NULL DEFAULT 0,
    payoutsEnabled           BIT NOT NULL DEFAULT 0,
    detailsSubmitted         BIT NOT NULL DEFAULT 0,
    identitySubmitted        BIT NOT NULL DEFAULT 0,   -- KYC identity (name/DOB/address) submitted → skip re-asking on reload
    hasExternalAccount       BIT NOT NULL DEFAULT 0,   -- bank account/debit card actually on file
    externalAccountLast4     NVARCHAR(4) NULL,
    externalAccountType      NVARCHAR(20) NULL,        -- bank_account | card
    externalAccountBankName  NVARCHAR(100) NULL,
    created_At               DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at               DATETIME2 NULL,
    CONSTRAINT UQ_stripeAccounts_client UNIQUE (clientId, companyId)
)
GO

-- Backfill for pre-existing databases (no-op if the table was just created above)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.stripeConnectedAccounts') AND name = 'hasExternalAccount')
ALTER TABLE [dbo].[stripeConnectedAccounts] ADD
    hasExternalAccount       BIT NOT NULL DEFAULT 0,
    externalAccountLast4     NVARCHAR(4) NULL,
    externalAccountType      NVARCHAR(20) NULL,
    externalAccountBankName  NVARCHAR(100) NULL
GO

-- Backfill identitySubmitted for pre-existing databases (no-op on fresh create).
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.stripeConnectedAccounts') AND name = 'identitySubmitted')
ALTER TABLE [dbo].[stripeConnectedAccounts] ADD identitySubmitted BIT NOT NULL DEFAULT 0
GO

-- Backfill ToS acceptance for pre-existing databases (no-op on fresh create).
-- Stripe itself already requires + stores tos_acceptance{date,ip} on the Custom
-- account (legal source of truth) — these columns mirror that locally so our
-- own DB/admin screens can show "¿aceptó los términos?" without an extra
-- Stripe API call per client.
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.stripeConnectedAccounts') AND name = 'tosAccepted')
ALTER TABLE [dbo].[stripeConnectedAccounts] ADD
    tosAccepted    BIT NOT NULL DEFAULT 0,
    tosAcceptedAt  DATETIME2 NULL
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
    stripePayoutId          NVARCHAR(100) NULL,
    failureReason           NVARCHAR(500) NULL,
    created_At              DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at              DATETIME2 NULL,
)
GO

-- Backfill for pre-existing databases (no-op if the table was just created above)
IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID('dbo.stripeTransactions') AND name = 'stripePayoutId')
ALTER TABLE [dbo].[stripeTransactions] ADD stripePayoutId NVARCHAR(100) NULL
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
        DECLARE @action                  NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].action')
        DECLARE @clientId                INT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].clientId')
        DECLARE @companyId               INT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].companyId')
        DECLARE @connectedAccountId      NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].connectedAccountId')
        DECLARE @chargesEnabled          BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].chargesEnabled')
        DECLARE @payoutsEnabled          BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].payoutsEnabled')
        DECLARE @detailsSubmitted        BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].detailsSubmitted')
        DECLARE @identitySubmitted       BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].identitySubmitted')
        DECLARE @hasExternalAccount      BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].hasExternalAccount')
        DECLARE @externalAccountLast4    NVARCHAR(4)   = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].externalAccountLast4')
        DECLARE @externalAccountType     NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].externalAccountType')
        DECLARE @externalAccountBankName NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].externalAccountBankName')
        DECLARE @tosAccepted             BIT           = JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].tosAccepted')
        DECLARE @tosAcceptedAt           DATETIME2     = TRY_CONVERT(DATETIME2, JSON_VALUE(@pjsonfile, '$.stripeAccounts[0].tosAcceptedAt'), 127)

        IF @action = 'upsert'
        BEGIN
            MERGE [dbo].[stripeConnectedAccounts] AS target
            USING (SELECT @clientId AS clientId, @companyId AS companyId) AS source
                ON target.clientId = source.clientId AND target.companyId = source.companyId
            WHEN MATCHED THEN
                UPDATE SET connectedAccountId      = ISNULL(@connectedAccountId,      target.connectedAccountId),
                           chargesEnabled          = ISNULL(@chargesEnabled,          target.chargesEnabled),
                           payoutsEnabled          = ISNULL(@payoutsEnabled,          target.payoutsEnabled),
                           detailsSubmitted        = ISNULL(@detailsSubmitted,        target.detailsSubmitted),
                           identitySubmitted       = ISNULL(@identitySubmitted,       target.identitySubmitted),
                           hasExternalAccount      = ISNULL(@hasExternalAccount,      target.hasExternalAccount),
                           externalAccountLast4    = ISNULL(@externalAccountLast4,    target.externalAccountLast4),
                           externalAccountType     = ISNULL(@externalAccountType,     target.externalAccountType),
                           externalAccountBankName = ISNULL(@externalAccountBankName, target.externalAccountBankName),
                           -- Sticky: una vez aceptado, nunca se revierte a 0 en
                           -- upserts posteriores que no traen tosAccepted (p.ej.
                           -- attach_external_bank_account).
                           tosAccepted             = CASE WHEN @tosAccepted = 1 THEN 1 ELSE target.tosAccepted END,
                           tosAcceptedAt           = ISNULL(@tosAcceptedAt,           target.tosAcceptedAt),
                           updated_at              = GETUTCDATE()
            WHEN NOT MATCHED THEN
                INSERT (clientId, companyId, connectedAccountId, chargesEnabled, payoutsEnabled, detailsSubmitted,
                        identitySubmitted, hasExternalAccount, externalAccountLast4, externalAccountType, externalAccountBankName,
                        tosAccepted, tosAcceptedAt)
                VALUES (@clientId, @companyId, @connectedAccountId,
                        ISNULL(@chargesEnabled, 0), ISNULL(@payoutsEnabled, 0), ISNULL(@detailsSubmitted, 0),
                        ISNULL(@identitySubmitted, 0), ISNULL(@hasExternalAccount, 0), @externalAccountLast4, @externalAccountType, @externalAccountBankName,
                        ISNULL(@tosAccepted, 0), @tosAcceptedAt);

            SELECT (SELECT TOP 1 * FROM [dbo].[stripeConnectedAccounts]
                    WHERE clientId = @clientId AND companyId = @companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 connectedAccountId, clientId, companyId,
                        chargesEnabled, payoutsEnabled, detailsSubmitted, identitySubmitted,
                        hasExternalAccount, externalAccountLast4, externalAccountType, externalAccountBankName,
                        tosAccepted, CONVERT(NVARCHAR, tosAcceptedAt, 127) AS tosAcceptedAt,
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
        DECLARE @stripePayoutId         NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].stripePayoutId')
        DECLARE @failureReason          NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].failureReason')
        DECLARE @clientId               INT           = JSON_VALUE(@pjsonfile, '$.stripeTransactions[0].clientId')

        IF @action = 'insert'
        BEGIN
            INSERT INTO [dbo].[stripeTransactions]
                (companyId, loanId, proposalId, fromClientId, toClientId, amount, currency,
                 paymentType, status, stripePaymentIntentId, stripeTransferId, stripePayoutId, failureReason)
            VALUES
                (@companyId, @loanId, @proposalId, @fromClientId, @toClientId, @amount, @currency,
                 @paymentType, @status, @stripePaymentIntentId, @stripeTransferId, @stripePayoutId, @failureReason)

            SELECT (SELECT transactionId, status, stripePaymentIntentId, stripePayoutId, amount, currency
                    FROM [dbo].[stripeTransactions]
                    WHERE transactionId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'update_status'
        BEGIN
            -- Capture the PREVIOUS status so callers can act exactly once on
            -- the pending→succeeded transition (e.g. credit a wallet top-up)
            -- even when both the app's confirm call and the Stripe webhook
            -- report the same intent.
            DECLARE @prev TABLE (prevStatus NVARCHAR(20));

            UPDATE [dbo].[stripeTransactions]
            SET status        = @status,
                failureReason = ISNULL(@failureReason, failureReason),
                updated_at    = GETUTCDATE()
            OUTPUT deleted.status INTO @prev
            WHERE stripePaymentIntentId = @stripePaymentIntentId
              AND (@companyId IS NULL OR companyId = @companyId)

            SELECT (SELECT TOP 1 transactionId, status,
                           (SELECT TOP 1 prevStatus FROM @prev) AS prevStatus,
                           stripePaymentIntentId, amount, currency,
                           paymentType, fromClientId, toClientId, companyId
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
                        stripePaymentIntentId, stripeTransferId, stripePayoutId, failureReason,
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
