-- ============================================================
-- Wallet, Installments, and Saved Payment Methods
-- Run this script once in your Azure SQL database
-- ============================================================

-- ── Table: clientWallets ────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'clientWallets')
CREATE TABLE [dbo].[clientWallets] (
    walletId          INT IDENTITY PRIMARY KEY,
    clientId          INT NOT NULL,
    companyId         INT NOT NULL,
    availableBalance  DECIMAL(18,2) NOT NULL DEFAULT 0,
    reservedBalance   DECIMAL(18,2) NOT NULL DEFAULT 0,
    totalTopUps       DECIMAL(18,2) NOT NULL DEFAULT 0,
    totalDisbursed    DECIMAL(18,2) NOT NULL DEFAULT 0,
    totalRepaid       DECIMAL(18,2) NOT NULL DEFAULT 0,
    updatedAt         DATETIME2 NULL,
    CONSTRAINT UQ_clientWallets UNIQUE (clientId, companyId)
)
GO

-- ── Table: savedPaymentMethods ──────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'savedPaymentMethods')
CREATE TABLE [dbo].[savedPaymentMethods] (
    methodId                INT IDENTITY PRIMARY KEY,
    clientId                INT NOT NULL,
    companyId               INT NOT NULL,
    stripePaymentMethodId   NVARCHAR(100) NOT NULL,
    last4                   NVARCHAR(4) NULL,
    brand                   NVARCHAR(20) NULL,
    expiryMonth             INT NULL,
    expiryYear              INT NULL,
    isDefault               BIT NOT NULL DEFAULT 1,
    createdAt               DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updatedAt               DATETIME2 NULL,
    CONSTRAINT UQ_savedPaymentMethods UNIQUE (clientId, companyId)
)
GO

-- ── Table: loanInstallments ─────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'loanInstallments')
CREATE TABLE [dbo].[loanInstallments] (
    installmentId           INT IDENTITY PRIMARY KEY,
    loanId                  INT NOT NULL,
    clientId                INT NOT NULL,
    companyId               INT NOT NULL,
    lenderId                INT NOT NULL,
    installmentNumber       INT NOT NULL,
    dueDate                 DATE NOT NULL,
    amount                  DECIMAL(18,2) NOT NULL,
    principal               DECIMAL(18,2) NOT NULL,
    interest                DECIMAL(18,2) NOT NULL,
    remainingBalance        DECIMAL(18,2) NOT NULL,
    status                  NVARCHAR(20) NOT NULL DEFAULT 'pending',
                            -- pending | paid | failed | delinquent | waived
    stripePaymentIntentId   NVARCHAR(100) NULL,
    failureReason           NVARCHAR(500) NULL,
    attemptCount            INT NOT NULL DEFAULT 0,
    lastAttemptAt           DATETIME2 NULL,
    paidAt                  DATETIME2 NULL,
    createdAt               DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
)
GO

-- ============================================================
-- sp_clientWallets
-- ============================================================
IF OBJECT_ID('dbo.sp_clientWallets', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_clientWallets;
GO

CREATE PROCEDURE [dbo].[sp_clientWallets]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action     NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.wallets[0].action')
        DECLARE @clientId   INT           = JSON_VALUE(@pjsonfile, '$.wallets[0].clientId')
        DECLARE @companyId  INT           = JSON_VALUE(@pjsonfile, '$.wallets[0].companyId')
        DECLARE @amountMXN  DECIMAL(18,2) = ISNULL(JSON_VALUE(@pjsonfile, '$.wallets[0].amountMXN'), 0)
        DECLARE @creditType NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.wallets[0].creditType')
        DECLARE @debitType  NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.wallets[0].debitType')

        -- Ensure wallet row exists
        IF NOT EXISTS (SELECT 1 FROM [dbo].[clientWallets] WHERE clientId=@clientId AND companyId=@companyId)
            INSERT INTO [dbo].[clientWallets] (clientId, companyId) VALUES (@clientId, @companyId)

        IF @action = 'get'
        BEGIN
            SELECT (SELECT availableBalance, reservedBalance, totalTopUps, totalDisbursed, totalRepaid,
                           CONVERT(NVARCHAR,updatedAt,127) AS updatedAt
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'credit'
        BEGIN
            UPDATE [dbo].[clientWallets]
            SET availableBalance = availableBalance + @amountMXN,
                totalTopUps      = totalTopUps + CASE WHEN @creditType='top_up' THEN @amountMXN ELSE 0 END,
                totalRepaid      = totalRepaid + CASE WHEN @creditType='repayment_received' THEN @amountMXN ELSE 0 END,
                updatedAt        = GETUTCDATE()
            WHERE clientId=@clientId AND companyId=@companyId

            SELECT (SELECT availableBalance, reservedBalance, totalTopUps, totalDisbursed, totalRepaid
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'debit'
        BEGIN
            IF (SELECT availableBalance FROM [dbo].[clientWallets] WHERE clientId=@clientId AND companyId=@companyId) < @amountMXN
            BEGIN
                SELECT '{"error":"Saldo insuficiente en cartera"}' AS [jsonResult]
                RETURN
            END

            UPDATE [dbo].[clientWallets]
            SET availableBalance = availableBalance - @amountMXN,
                reservedBalance  = CASE WHEN @debitType='disbursement'
                                        THEN GREATEST(0, reservedBalance - @amountMXN)
                                        ELSE reservedBalance END,
                totalDisbursed   = totalDisbursed + @amountMXN,
                updatedAt        = GETUTCDATE()
            WHERE clientId=@clientId AND companyId=@companyId

            SELECT (SELECT availableBalance, reservedBalance, totalTopUps, totalDisbursed, totalRepaid
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'reserve'
        BEGIN
            IF (SELECT availableBalance FROM [dbo].[clientWallets] WHERE clientId=@clientId AND companyId=@companyId) < @amountMXN
            BEGIN
                SELECT '{"error":"Saldo insuficiente para reservar"}' AS [jsonResult]
                RETURN
            END

            UPDATE [dbo].[clientWallets]
            SET availableBalance = availableBalance - @amountMXN,
                reservedBalance  = reservedBalance  + @amountMXN,
                updatedAt        = GETUTCDATE()
            WHERE clientId=@clientId AND companyId=@companyId

            SELECT (SELECT availableBalance, reservedBalance
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'release'
        BEGIN
            -- Undo a prior 'reserve' when the disbursement it was held for
            -- fails, without touching totalDisbursed (no money actually moved).
            UPDATE [dbo].[clientWallets]
            SET availableBalance = availableBalance + LEAST(@amountMXN, reservedBalance),
                reservedBalance  = GREATEST(0, reservedBalance - @amountMXN),
                updatedAt        = GETUTCDATE()
            WHERE clientId=@clientId AND companyId=@companyId

            SELECT (SELECT availableBalance, reservedBalance
                    FROM [dbo].[clientWallets]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT w.clientId, w.companyId, w.availableBalance, w.reservedBalance,
                        w.totalTopUps, w.totalDisbursed, w.totalRepaid,
                        c.first_name, c.last_name
                 FROM [dbo].[clientWallets] w
                 LEFT JOIN [dbo].[clients] c ON c.clientId = w.clientId
                 WHERE w.companyId = @companyId
                 ORDER BY w.availableBalance DESC
                 FOR JSON PATH, ROOT('wallets')),
                '{"wallets":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_savedPaymentMethods
-- ============================================================
IF OBJECT_ID('dbo.sp_savedPaymentMethods', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_savedPaymentMethods;
GO

CREATE PROCEDURE [dbo].[sp_savedPaymentMethods]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action    NVARCHAR(10)   = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].action')
        DECLARE @clientId  INT            = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].clientId')
        DECLARE @companyId INT            = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].companyId')
        DECLARE @pmId      NVARCHAR(100)  = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].stripePaymentMethodId')
        DECLARE @last4     NVARCHAR(4)    = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].last4')
        DECLARE @brand     NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].brand')
        DECLARE @expMonth  INT            = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].expiryMonth')
        DECLARE @expYear   INT            = JSON_VALUE(@pjsonfile, '$.paymentMethods[0].expiryYear')

        IF @action = 'upsert'
        BEGIN
            MERGE [dbo].[savedPaymentMethods] AS target
            USING (SELECT @clientId AS clientId, @companyId AS companyId) AS src
                ON target.clientId = src.clientId AND target.companyId = src.companyId
            WHEN MATCHED THEN
                UPDATE SET stripePaymentMethodId=@pmId, last4=@last4, brand=@brand,
                           expiryMonth=@expMonth, expiryYear=@expYear, updatedAt=GETUTCDATE()
            WHEN NOT MATCHED THEN
                INSERT (clientId, companyId, stripePaymentMethodId, last4, brand, expiryMonth, expiryYear)
                VALUES (@clientId, @companyId, @pmId, @last4, @brand, @expMonth, @expYear);

            SELECT (SELECT TOP 1 stripePaymentMethodId, last4, brand, expiryMonth, expiryYear
                    FROM [dbo].[savedPaymentMethods]
                    WHERE clientId=@clientId AND companyId=@companyId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL(
                (SELECT TOP 1 stripePaymentMethodId, last4, brand, expiryMonth, expiryYear
                 FROM [dbo].[savedPaymentMethods]
                 WHERE clientId=@clientId AND companyId=@companyId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
                'null'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_loanInstallments
-- ============================================================
IF OBJECT_ID('dbo.sp_loanInstallments', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loanInstallments;
GO

CREATE PROCEDURE [dbo].[sp_loanInstallments]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action          NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.installments[0].action')
        DECLARE @installmentId   INT           = JSON_VALUE(@pjsonfile, '$.installments[0].installmentId')
        DECLARE @loanId          INT           = JSON_VALUE(@pjsonfile, '$.installments[0].loanId')
        DECLARE @clientId        INT           = JSON_VALUE(@pjsonfile, '$.installments[0].clientId')
        DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.installments[0].companyId')
        DECLARE @lenderId        INT           = JSON_VALUE(@pjsonfile, '$.installments[0].lenderId')
        DECLARE @instNum         INT           = JSON_VALUE(@pjsonfile, '$.installments[0].installmentNumber')
        DECLARE @dueDate         DATE          = JSON_VALUE(@pjsonfile, '$.installments[0].dueDate')
        DECLARE @amount          DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.installments[0].amount')
        DECLARE @principal       DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.installments[0].principal')
        DECLARE @interest        DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.installments[0].interest')
        DECLARE @remaining       DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.installments[0].remainingBalance')
        DECLARE @status          NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.installments[0].status')
        DECLARE @intentId        NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.installments[0].stripePaymentIntentId')
        DECLARE @failReason      NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.installments[0].failureReason')
        DECLARE @attemptCount    INT           = JSON_VALUE(@pjsonfile, '$.installments[0].attemptCount')
        DECLARE @paidAt          DATETIME2     = JSON_VALUE(@pjsonfile, '$.installments[0].paidAt')
        DECLARE @lastAttemptAt   DATETIME2     = JSON_VALUE(@pjsonfile, '$.installments[0].lastAttemptAt')
        DECLARE @asOfDate        DATE          = ISNULL(JSON_VALUE(@pjsonfile, '$.installments[0].asOfDate'), CAST(GETUTCDATE() AS DATE))

        IF @action = 'insert'
        BEGIN
            INSERT INTO [dbo].[loanInstallments]
                (loanId, clientId, companyId, lenderId, installmentNumber, dueDate,
                 amount, principal, interest, remainingBalance, status)
            VALUES
                (@loanId, @clientId, @companyId, @lenderId, @instNum, @dueDate,
                 @amount, @principal, @interest, @remaining, ISNULL(@status,'pending'))

            SELECT (SELECT SCOPE_IDENTITY() AS installmentId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 'update_status'
        BEGIN
            UPDATE [dbo].[loanInstallments]
            SET status                  = ISNULL(@status, status),
                stripePaymentIntentId   = ISNULL(@intentId, stripePaymentIntentId),
                failureReason           = ISNULL(@failReason, failureReason),
                attemptCount            = ISNULL(@attemptCount, attemptCount),
                lastAttemptAt           = ISNULL(@lastAttemptAt, lastAttemptAt),
                paidAt                  = ISNULL(@paidAt, paidAt)
            WHERE installmentId = @installmentId

            SELECT '{"message":"updated"}' AS [jsonResult]
        END

        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL(
                (SELECT installmentId, loanId, installmentNumber,
                        CONVERT(NVARCHAR,dueDate,23) AS dueDate,
                        amount, principal, interest, remainingBalance, status,
                        attemptCount,
                        CONVERT(NVARCHAR,paidAt,127) AS paidAt
                 FROM [dbo].[loanInstallments]
                 WHERE loanId=@loanId AND companyId=@companyId
                 ORDER BY installmentNumber
                 FOR JSON PATH, ROOT('installments')),
                '{"installments":[]}'
            ) AS [jsonResult]
        END

        ELSE IF @action = 'due'
        BEGIN
            -- Return all pending/failed installments due today or earlier (for auto-charge)
            SELECT ISNULL(
                (SELECT installmentId, loanId, clientId, lenderId, companyId,
                        installmentNumber,
                        CONVERT(NVARCHAR,dueDate,23) AS dueDate,
                        amount, attemptCount
                 FROM [dbo].[loanInstallments]
                 WHERE companyId = @companyId
                   AND dueDate <= @asOfDate
                   AND status IN ('pending','failed')
                   AND attemptCount < 3
                 ORDER BY dueDate
                 FOR JSON PATH, ROOT('installments')),
                '{"installments":[]}'
            ) AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
