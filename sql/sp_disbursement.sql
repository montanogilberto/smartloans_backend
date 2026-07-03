-- ============================================================
-- Disbursement — loan transfer tracking
-- Table:    loanDisbursements
-- SP:       sp_disbursement
-- Actions:  initiate | confirm_sent | confirm_received
--           get_status | list_disbursements | failed
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'loanDisbursements')
CREATE TABLE [dbo].[loanDisbursements] (
    disbursementId      INT IDENTITY PRIMARY KEY,
    companyId           INT NOT NULL,
    loanId              INT NOT NULL,
    contractId          INT NULL,
    borrowerClientId    INT NOT NULL,
    lenderClientId      INT NOT NULL,
    borrowerUserId      INT NULL,               -- push target
    lenderUserId        INT NULL,               -- push target
    amount              DECIMAL(14,2) NOT NULL,
    currency            NVARCHAR(10) NOT NULL DEFAULT 'MXN',
    disbursementStatus  NVARCHAR(20) NOT NULL DEFAULT 'pending',
                                                -- pending | initiated | sent | received | failed
    transferReference   NVARCHAR(200) NULL,     -- bank transfer ID / SPEI tracking
    transferMethod      NVARCHAR(50) NULL,       -- SPEI | cash | other
    sentAt              DATETIME2 NULL,
    receivedAt          DATETIME2 NULL,
    errorNote           NVARCHAR(500) NULL,
    notes               NVARCHAR(MAX) NULL,
    created_At          DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at          DATETIME2 NULL
)
GO

-- ── SP ───────────────────────────────────────────────────────

IF OBJECT_ID('dbo.sp_disbursement', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_disbursement;
GO

CREATE PROCEDURE [dbo].[sp_disbursement]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.disbursement[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].companyId')
    DECLARE @disbursementId  INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].disbursementId')
    DECLARE @loanId          INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].loanId')
    DECLARE @clientId        INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].clientId')

    -- ── initiate ─────────────────────────────────────────────
    IF @action = 'initiate'
    BEGIN
        DECLARE @contractId       INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].contractId')
        DECLARE @borrowerClientId INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].borrowerClientId')
        DECLARE @lenderClientId   INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].lenderClientId')
        DECLARE @borrowerUserId   INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].borrowerUserId')
        DECLARE @lenderUserId     INT           = JSON_VALUE(@pjsonfile, '$.disbursement[0].lenderUserId')
        DECLARE @amount           DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.disbursement[0].amount')
        DECLARE @currency         NVARCHAR(10)  = ISNULL(JSON_VALUE(@pjsonfile, '$.disbursement[0].currency'), 'MXN')
        DECLARE @transferMethod   NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.disbursement[0].transferMethod')
        DECLARE @initNotes        NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.disbursement[0].notes')

        INSERT INTO loanDisbursements
            (companyId, loanId, contractId, borrowerClientId, lenderClientId,
             borrowerUserId, lenderUserId, amount, currency, disbursementStatus,
             transferMethod, notes)
        VALUES
            (@companyId, @loanId, @contractId, @borrowerClientId, @lenderClientId,
             @borrowerUserId, @lenderUserId, @amount, @currency, 'initiated',
             @transferMethod, @initNotes)

        DECLARE @newDisbId INT = SCOPE_IDENTITY()

        SELECT (
            SELECT disbursementId, companyId, loanId, contractId, disbursementStatus,
                   amount, currency, transferMethod,
                   -- push target = lender (they must send the money)
                   @lenderUserId AS lenderUserId,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM loanDisbursements WHERE disbursementId = @newDisbId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── confirm_sent ──────────────────────────────────────────
    ELSE IF @action = 'confirm_sent'
    BEGIN
        DECLARE @transferReference NVARCHAR(200) = JSON_VALUE(@pjsonfile, '$.disbursement[0].transferReference')
        DECLARE @sentNotes         NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.disbursement[0].notes')

        UPDATE loanDisbursements SET
            disbursementStatus = 'sent',
            transferReference  = ISNULL(@transferReference, transferReference),
            sentAt             = GETUTCDATE(),
            notes              = ISNULL(@sentNotes, notes),
            updated_at         = GETUTCDATE()
        WHERE disbursementId = @disbursementId AND companyId = @companyId

        DECLARE @sentBorrowerUserId INT
        DECLARE @sentAmount         DECIMAL(14,2)
        SELECT @sentBorrowerUserId = borrowerUserId, @sentAmount = amount
        FROM loanDisbursements WHERE disbursementId = @disbursementId

        SELECT (
            SELECT @disbursementId AS disbursementId, 'sent' AS disbursementStatus,
                   @sentAmount AS amount, @transferReference AS transferReference,
                   -- push target = borrower (waiting for the money)
                   @sentBorrowerUserId AS borrowerUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── confirm_received ──────────────────────────────────────
    ELSE IF @action = 'confirm_received'
    BEGIN
        UPDATE loanDisbursements SET
            disbursementStatus = 'received',
            receivedAt         = GETUTCDATE(),
            updated_at         = GETUTCDATE()
        WHERE disbursementId = @disbursementId AND companyId = @companyId

        -- Mark the loan as active
        UPDATE dbo.loans SET
            loanStatus       = 'active',
            disbursementDate = GETUTCDATE(),
            updated_at       = GETUTCDATE()
        WHERE loanId = @loanId AND companyId = @companyId

        DECLARE @rcvBorrowerUserId INT
        DECLARE @rcvLenderUserId   INT
        DECLARE @rcvAmount         DECIMAL(14,2)
        SELECT @rcvBorrowerUserId = borrowerUserId,
               @rcvLenderUserId   = lenderUserId,
               @rcvAmount         = amount
        FROM loanDisbursements WHERE disbursementId = @disbursementId

        SELECT (
            SELECT @disbursementId AS disbursementId, 'received' AS disbursementStatus,
                   @rcvAmount AS amount,
                   -- push both parties
                   @rcvBorrowerUserId AS borrowerUserId, @rcvLenderUserId AS lenderUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── get_status ────────────────────────────────────────────
    ELSE IF @action = 'get_status'
    BEGIN
        SELECT ISNULL(
            (SELECT TOP 1
                disbursementId, companyId, loanId, contractId, disbursementStatus,
                amount, currency, transferReference, transferMethod,
                borrowerClientId, lenderClientId,
                CONVERT(NVARCHAR, sentAt, 127)     AS sentAt,
                CONVERT(NVARCHAR, receivedAt, 127) AS receivedAt,
                errorNote, notes,
                CONVERT(NVARCHAR, created_At, 127) AS created_At,
                CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM loanDisbursements
             WHERE loanId = @loanId AND companyId = @companyId
             ORDER BY created_At DESC
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    -- ── list_disbursements ────────────────────────────────────
    ELSE IF @action = 'list_disbursements'
    BEGIN
        SELECT ISNULL(
            (SELECT disbursementId, loanId, contractId, disbursementStatus,
                    amount, currency, transferMethod,
                    borrowerClientId, lenderClientId,
                    CONVERT(NVARCHAR, sentAt, 127)     AS sentAt,
                    CONVERT(NVARCHAR, receivedAt, 127) AS receivedAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM loanDisbursements
             WHERE companyId = @companyId
               AND (borrowerClientId = @clientId OR lenderClientId = @clientId)
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── failed ────────────────────────────────────────────────
    ELSE IF @action = 'failed'
    BEGIN
        DECLARE @errorNote NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.disbursement[0].errorNote')

        UPDATE loanDisbursements SET
            disbursementStatus = 'failed',
            errorNote          = @errorNote,
            updated_at         = GETUTCDATE()
        WHERE disbursementId = @disbursementId AND companyId = @companyId

        DECLARE @failBorrowerUserId INT
        DECLARE @failLenderUserId   INT
        SELECT @failBorrowerUserId = borrowerUserId,
               @failLenderUserId   = lenderUserId
        FROM loanDisbursements WHERE disbursementId = @disbursementId

        SELECT (
            SELECT @disbursementId AS disbursementId, 'failed' AS disbursementStatus,
                   @errorNote AS errorNote,
                   -- push both parties
                   @failBorrowerUserId AS borrowerUserId, @failLenderUserId AS lenderUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
