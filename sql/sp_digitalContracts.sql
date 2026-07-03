-- ============================================================
-- Digital Contracts — loan contracts and pagarés
-- Tables:   loanContracts, loanContractSignatures
-- SP:       sp_digitalContracts
-- Actions:  create_contract | sign_contract | get_contract
--           list_contracts  | void_contract | download_pdf
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'loanContracts')
CREATE TABLE [dbo].[loanContracts] (
    contractId          INT IDENTITY PRIMARY KEY,
    companyId           INT NOT NULL,
    loanId              INT NOT NULL,
    conversationId      INT NULL,
    borrowerClientId    INT NOT NULL,
    lenderClientId      INT NOT NULL,
    borrowerUserId      INT NULL,
    lenderUserId        INT NULL,
    contractType        NVARCHAR(20) NOT NULL DEFAULT 'contract',  -- contract | pagare
    principalAmount     DECIMAL(14,2) NOT NULL,
    interestRate        DECIMAL(6,4) NOT NULL,
    termMonths          INT NOT NULL,
    paymentFrequency    NVARCHAR(20) NOT NULL DEFAULT 'monthly',
    startDate           DATETIME2 NULL,
    endDate             DATETIME2 NULL,
    contractStatus      NVARCHAR(20) NOT NULL DEFAULT 'pending',
                                                 -- pending | borrower_signed | fully_signed | void
    pdfBlobUrl          NVARCHAR(500) NULL,
    contractHtml        NVARCHAR(MAX) NULL,
    notes               NVARCHAR(MAX) NULL,
    created_At          DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at          DATETIME2 NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'loanContractSignatures')
CREATE TABLE [dbo].[loanContractSignatures] (
    signatureId         INT IDENTITY PRIMARY KEY,
    contractId          INT NOT NULL,
    signerClientId      INT NOT NULL,
    signerUserId        INT NULL,
    signerRole          NVARCHAR(20) NOT NULL,   -- borrower | lender
    signatureImageUrl   NVARCHAR(500) NULL,
    ipAddress           NVARCHAR(50) NULL,
    deviceFingerprint   NVARCHAR(200) NULL,
    biometricVerified   BIT NOT NULL DEFAULT 0,
    signedAt            DATETIME2 NOT NULL DEFAULT GETUTCDATE()
)
GO

-- ── SP ───────────────────────────────────────────────────────

IF OBJECT_ID('dbo.sp_digitalContracts', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_digitalContracts;
GO

CREATE PROCEDURE [dbo].[sp_digitalContracts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.contract[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.contract[0].companyId')
    DECLARE @contractId      INT           = JSON_VALUE(@pjsonfile, '$.contract[0].contractId')
    DECLARE @loanId          INT           = JSON_VALUE(@pjsonfile, '$.contract[0].loanId')
    DECLARE @clientId        INT           = JSON_VALUE(@pjsonfile, '$.contract[0].clientId')

    -- ── create_contract ──────────────────────────────────────
    IF @action = 'create_contract'
    BEGIN
        DECLARE @conversationId   INT           = JSON_VALUE(@pjsonfile, '$.contract[0].conversationId')
        DECLARE @borrowerClientId INT           = JSON_VALUE(@pjsonfile, '$.contract[0].borrowerClientId')
        DECLARE @lenderClientId   INT           = JSON_VALUE(@pjsonfile, '$.contract[0].lenderClientId')
        DECLARE @borrowerUserId   INT           = JSON_VALUE(@pjsonfile, '$.contract[0].borrowerUserId')
        DECLARE @lenderUserId     INT           = JSON_VALUE(@pjsonfile, '$.contract[0].lenderUserId')
        DECLARE @contractType     NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.contract[0].contractType'), 'contract')
        DECLARE @principalAmount  DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.contract[0].principalAmount')
        DECLARE @interestRate     DECIMAL(6,4)  = JSON_VALUE(@pjsonfile, '$.contract[0].interestRate')
        DECLARE @termMonths       INT           = JSON_VALUE(@pjsonfile, '$.contract[0].termMonths')
        DECLARE @paymentFrequency NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.contract[0].paymentFrequency'), 'monthly')
        DECLARE @startDate        DATETIME2     = JSON_VALUE(@pjsonfile, '$.contract[0].startDate')
        DECLARE @endDate          DATETIME2     = JSON_VALUE(@pjsonfile, '$.contract[0].endDate')
        DECLARE @contractHtml     NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.contract[0].contractHtml')
        DECLARE @notes            NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.contract[0].notes')

        INSERT INTO loanContracts
            (companyId, loanId, conversationId, borrowerClientId, lenderClientId,
             borrowerUserId, lenderUserId, contractType, principalAmount, interestRate,
             termMonths, paymentFrequency, startDate, endDate, contractHtml, notes)
        VALUES
            (@companyId, @loanId, @conversationId, @borrowerClientId, @lenderClientId,
             @borrowerUserId, @lenderUserId, @contractType, @principalAmount, @interestRate,
             @termMonths, @paymentFrequency, @startDate, @endDate, @contractHtml, @notes)

        DECLARE @newContractId INT = SCOPE_IDENTITY()

        SELECT (
            SELECT TOP 1
                contractId, companyId, loanId, borrowerClientId, lenderClientId,
                borrowerUserId, lenderUserId, contractType, principalAmount,
                interestRate, termMonths, paymentFrequency, contractStatus,
                CONVERT(NVARCHAR, startDate, 127) AS startDate,
                CONVERT(NVARCHAR, endDate, 127)   AS endDate,
                CONVERT(NVARCHAR, created_At, 127) AS created_At,
                -- targetUserId for push = borrower (must sign first)
                @borrowerUserId AS targetUserId
            FROM loanContracts WHERE contractId = @newContractId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── sign_contract ─────────────────────────────────────────
    ELSE IF @action = 'sign_contract'
    BEGIN
        DECLARE @signerClientId    INT          = JSON_VALUE(@pjsonfile, '$.contract[0].signerClientId')
        DECLARE @signerUserId      INT          = JSON_VALUE(@pjsonfile, '$.contract[0].signerUserId')
        DECLARE @signerRole        NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.contract[0].signerRole')
        DECLARE @signatureImageUrl NVARCHAR(500)= JSON_VALUE(@pjsonfile, '$.contract[0].signatureImageUrl')
        DECLARE @ipAddress         NVARCHAR(50) = JSON_VALUE(@pjsonfile, '$.contract[0].ipAddress')
        DECLARE @deviceFingerprint NVARCHAR(200)= JSON_VALUE(@pjsonfile, '$.contract[0].deviceFingerprint')
        DECLARE @biometricVerified BIT          = ISNULL(JSON_VALUE(@pjsonfile, '$.contract[0].biometricVerified'), 0)

        INSERT INTO loanContractSignatures
            (contractId, signerClientId, signerUserId, signerRole,
             signatureImageUrl, ipAddress, deviceFingerprint, biometricVerified)
        VALUES
            (@contractId, @signerClientId, @signerUserId, @signerRole,
             @signatureImageUrl, @ipAddress, @deviceFingerprint, @biometricVerified)

        -- Advance contract status
        DECLARE @signatureCount INT
        SELECT @signatureCount = COUNT(*) FROM loanContractSignatures WHERE contractId = @contractId

        DECLARE @newStatus NVARCHAR(20) =
            CASE WHEN @signatureCount >= 2 THEN 'fully_signed' ELSE 'borrower_signed' END

        UPDATE loanContracts SET
            contractStatus = @newStatus,
            updated_at     = GETUTCDATE()
        WHERE contractId = @contractId

        -- Return target for push (other party)
        DECLARE @signTargetUserId INT
        SELECT @signTargetUserId =
            CASE WHEN @signerRole = 'borrower' THEN lenderUserId ELSE borrowerUserId END
        FROM loanContracts WHERE contractId = @contractId

        SELECT (
            SELECT @contractId AS contractId, @newStatus AS contractStatus,
                   @signatureCount AS signaturesCount, @signTargetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── get_contract ──────────────────────────────────────────
    ELSE IF @action = 'get_contract'
    BEGIN
        SELECT ISNULL(
            (SELECT TOP 1
                c.contractId, c.companyId, c.loanId, c.conversationId,
                c.borrowerClientId, c.lenderClientId, c.borrowerUserId, c.lenderUserId,
                c.contractType, c.principalAmount, c.interestRate, c.termMonths,
                c.paymentFrequency, c.contractStatus, c.pdfBlobUrl,
                CONVERT(NVARCHAR, c.startDate, 127)   AS startDate,
                CONVERT(NVARCHAR, c.endDate, 127)     AS endDate,
                CONVERT(NVARCHAR, c.created_At, 127)  AS created_At,
                CONVERT(NVARCHAR, c.updated_at, 127)  AS updated_at,
                -- Embedded signatures array
                (SELECT signatureId, signerClientId, signerRole, biometricVerified,
                        CONVERT(NVARCHAR, signedAt, 127) AS signedAt
                 FROM loanContractSignatures
                 WHERE contractId = c.contractId
                 FOR JSON PATH) AS signatures
             FROM loanContracts c
             WHERE c.contractId = @contractId AND c.companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    -- ── list_contracts ────────────────────────────────────────
    ELSE IF @action = 'list_contracts'
    BEGIN
        SELECT ISNULL(
            (SELECT contractId, companyId, loanId, contractType, contractStatus,
                    principalAmount, interestRate, termMonths, pdfBlobUrl,
                    borrowerClientId, lenderClientId,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM loanContracts
             WHERE companyId = @companyId
               AND (borrowerClientId = @clientId OR lenderClientId = @clientId)
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── void_contract ─────────────────────────────────────────
    ELSE IF @action = 'void_contract'
    BEGIN
        DECLARE @voidSignerUserId INT = JSON_VALUE(@pjsonfile, '$.contract[0].signerUserId')

        UPDATE loanContracts SET
            contractStatus = 'void',
            updated_at     = GETUTCDATE()
        WHERE contractId = @contractId AND companyId = @companyId
          AND contractStatus = 'pending'   -- can only void before any signature

        DECLARE @voidTargetUserId INT
        SELECT @voidTargetUserId =
            CASE WHEN borrowerUserId = @voidSignerUserId THEN lenderUserId ELSE borrowerUserId END
        FROM loanContracts WHERE contractId = @contractId

        SELECT (
            SELECT @contractId AS contractId, 'void' AS contractStatus,
                   @voidTargetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── download_pdf ──────────────────────────────────────────
    ELSE IF @action = 'download_pdf'
    BEGIN
        SELECT ISNULL(
            (SELECT TOP 1 contractId, contractType, contractStatus, pdfBlobUrl
             FROM loanContracts
             WHERE contractId = @contractId AND companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
