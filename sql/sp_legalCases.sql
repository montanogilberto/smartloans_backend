-- ============================================================
-- Legal Cases — loan recovery and juicio mercantil
-- Tables:   legalCases, legalCaseNotes
-- SP:       sp_legalCases
-- Actions:  open_case | assign_lawyer | get_expediente
--           list_cases | get_case | update_status
--           add_case_note | close_case | embargo_executed
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'legalCases')
CREATE TABLE [dbo].[legalCases] (
    caseId              INT IDENTITY PRIMARY KEY,
    companyId           INT NOT NULL,
    loanId              INT NOT NULL,
    borrowerClientId    INT NOT NULL,
    lenderClientId      INT NOT NULL,
    lenderUserId        INT NULL,               -- push target
    lawyerClientId      INT NULL,
    lawyerUserId        INT NULL,               -- push target
    lawyerName          NVARCHAR(200) NULL,
    caseStatus          NVARCHAR(30) NOT NULL DEFAULT 'open',
                                                -- open | demand_filed | judgment | embargo | closed
    caseStage           NVARCHAR(50) NULL,      -- free-text stage label
    overdueAmount       DECIMAL(14,2) NULL,
    recoveredAmount     DECIMAL(14,2) NULL,
    embargoExecutedAt   DATETIME2 NULL,
    closedAt            DATETIME2 NULL,
    statusNote          NVARCHAR(MAX) NULL,
    created_At          DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at          DATETIME2 NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'legalCaseNotes')
CREATE TABLE [dbo].[legalCaseNotes] (
    noteId          INT IDENTITY PRIMARY KEY,
    caseId          INT NOT NULL,
    authorClientId  INT NOT NULL,
    authorRole      NVARCHAR(20) NOT NULL,   -- lawyer | lender | system
    noteText        NVARCHAR(MAX) NOT NULL,
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE()
)
GO

-- ── SP ───────────────────────────────────────────────────────

IF OBJECT_ID('dbo.sp_legalCases', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_legalCases;
GO

CREATE PROCEDURE [dbo].[sp_legalCases]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.case[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.case[0].companyId')
    DECLARE @caseId          INT           = JSON_VALUE(@pjsonfile, '$.case[0].caseId')
    DECLARE @loanId          INT           = JSON_VALUE(@pjsonfile, '$.case[0].loanId')
    DECLARE @clientId        INT           = JSON_VALUE(@pjsonfile, '$.case[0].clientId')

    -- ── open_case ────────────────────────────────────────────
    IF @action = 'open_case'
    BEGIN
        DECLARE @borrowerClientId INT          = JSON_VALUE(@pjsonfile, '$.case[0].borrowerClientId')
        DECLARE @lenderClientId   INT          = JSON_VALUE(@pjsonfile, '$.case[0].lenderClientId')
        DECLARE @lenderUserId     INT          = JSON_VALUE(@pjsonfile, '$.case[0].lenderUserId')
        DECLARE @overdueAmount    DECIMAL(14,2)= JSON_VALUE(@pjsonfile, '$.case[0].overdueAmount')
        DECLARE @openStatusNote   NVARCHAR(MAX)= JSON_VALUE(@pjsonfile, '$.case[0].statusNote')

        -- Prevent duplicate open cases for same loan
        IF EXISTS (SELECT 1 FROM legalCases WHERE loanId = @loanId AND caseStatus NOT IN ('closed'))
        BEGIN
            SELECT (SELECT TOP 1 caseId, caseStatus, loanId
                    FROM legalCases WHERE loanId = @loanId AND caseStatus NOT IN ('closed')
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
            RETURN
        END

        INSERT INTO legalCases
            (companyId, loanId, borrowerClientId, lenderClientId, lenderUserId,
             overdueAmount, statusNote)
        VALUES
            (@companyId, @loanId, @borrowerClientId, @lenderClientId, @lenderUserId,
             @overdueAmount, @openStatusNote)

        DECLARE @newCaseId INT = SCOPE_IDENTITY()

        -- Auto system note
        INSERT INTO legalCaseNotes (caseId, authorClientId, authorRole, noteText)
        VALUES (@newCaseId, @lenderClientId, 'system', 'Caso de recuperación abierto automáticamente por incumplimiento de pago.')

        SELECT (
            SELECT caseId, companyId, loanId, caseStatus, overdueAmount, lenderUserId,
                   CONVERT(NVARCHAR, created_At, 127) AS created_At
            FROM legalCases WHERE caseId = @newCaseId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── assign_lawyer ─────────────────────────────────────────
    ELSE IF @action = 'assign_lawyer'
    BEGIN
        DECLARE @lawyerClientId INT          = JSON_VALUE(@pjsonfile, '$.case[0].lawyerClientId')
        DECLARE @lawyerUserId   INT          = JSON_VALUE(@pjsonfile, '$.case[0].lawyerUserId')
        DECLARE @lawyerName     NVARCHAR(200)= JSON_VALUE(@pjsonfile, '$.case[0].lawyerName')

        UPDATE legalCases SET
            lawyerClientId = @lawyerClientId,
            lawyerUserId   = @lawyerUserId,
            lawyerName     = @lawyerName,
            caseStatus     = 'demand_filed',
            updated_at     = GETUTCDATE()
        WHERE caseId = @caseId AND companyId = @companyId

        INSERT INTO legalCaseNotes (caseId, authorClientId, authorRole, noteText)
        VALUES (@caseId, @lawyerClientId, 'system',
                'Abogado ' + ISNULL(@lawyerName, '') + ' asignado al caso.')

        SELECT (
            SELECT @caseId AS caseId, 'demand_filed' AS caseStatus,
                   @lawyerUserId AS lawyerUserId, @lawyerName AS lawyerName,
                   -- push both parties
                   @lenderUserId AS lenderUserId, @lawyerUserId AS lawyerUserId2
            FROM legalCases WHERE caseId = @caseId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── get_expediente ────────────────────────────────────────
    -- Returns full digital expediente: case + loan + contracts + signatures + chat + payments + identity
    ELSE IF @action = 'get_expediente'
    BEGIN
        SELECT ISNULL(
            (SELECT
                lc.caseId, lc.caseStatus, lc.caseStage, lc.overdueAmount, lc.recoveredAmount,
                lc.lawyerName,
                CONVERT(NVARCHAR, lc.created_At, 127) AS caseOpenedAt,

                -- Loan snapshot
                (SELECT TOP 1 loanId, loanNumber, principalAmount, interestRate,
                              termMonths, paymentFrequency, loanStatus,
                              CONVERT(NVARCHAR, disbursementDate, 127) AS disbursementDate,
                              CONVERT(NVARCHAR, maturityDate, 127) AS maturityDate
                 FROM dbo.loans WHERE loanId = lc.loanId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS loan,

                -- Borrower identity
                (SELECT TOP 1 clientId, first_name, last_name, cellphone, email
                 FROM dbo.clients WHERE clientId = lc.borrowerClientId
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS borrower,

                -- Contracts + signatures
                (SELECT contractId, contractType, contractStatus, principalAmount,
                        interestRate, termMonths, pdfBlobUrl,
                        CONVERT(NVARCHAR, created_At, 127) AS created_At,
                        (SELECT signatureId, signerRole, biometricVerified,
                                CONVERT(NVARCHAR, signedAt, 127) AS signedAt
                         FROM dbo.loanContractSignatures
                         WHERE contractId = dc.contractId
                         FOR JSON PATH) AS signatures
                 FROM dbo.loanContracts dc
                 WHERE dc.loanId = lc.loanId
                 FOR JSON PATH) AS contracts,

                -- Payment history
                (SELECT TOP 50 *
                 FROM dbo.walletTransactions
                 WHERE loanId = lc.loanId
                 ORDER BY created_At
                 FOR JSON PATH) AS payments,

                -- Case notes
                (SELECT noteId, authorRole, noteText,
                        CONVERT(NVARCHAR, created_At, 127) AS created_At
                 FROM dbo.legalCaseNotes WHERE caseId = lc.caseId
                 ORDER BY created_At
                 FOR JSON PATH) AS notes

             FROM legalCases lc
             WHERE lc.caseId = @caseId AND lc.companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    -- ── list_cases ────────────────────────────────────────────
    ELSE IF @action = 'list_cases'
    BEGIN
        DECLARE @lawyerClientIdFilter INT         = JSON_VALUE(@pjsonfile, '$.case[0].lawyerClientId')
        DECLARE @statusFilter         NVARCHAR(30)= JSON_VALUE(@pjsonfile, '$.case[0].caseStatus')

        SELECT ISNULL(
            (SELECT caseId, companyId, loanId, caseStatus, caseStage, lawyerName,
                    overdueAmount, recoveredAmount,
                    borrowerClientId, lenderClientId, lawyerClientId,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM legalCases
             WHERE companyId = @companyId
               AND (@lawyerClientIdFilter IS NULL OR lawyerClientId = @lawyerClientIdFilter)
               AND (@clientId IS NULL OR lenderClientId = @clientId OR borrowerClientId = @clientId)
               AND (@statusFilter IS NULL OR caseStatus = @statusFilter)
             ORDER BY created_At DESC
             FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── get_case ──────────────────────────────────────────────
    ELSE IF @action = 'get_case'
    BEGIN
        SELECT ISNULL(
            (SELECT lc.caseId, lc.companyId, lc.loanId, lc.borrowerClientId, lc.lenderClientId,
                    lc.lenderUserId, lc.lawyerClientId, lc.lawyerUserId, lc.lawyerName,
                    lc.caseStatus, lc.caseStage, lc.overdueAmount, lc.recoveredAmount,
                    lc.statusNote,
                    CONVERT(NVARCHAR, lc.embargoExecutedAt, 127) AS embargoExecutedAt,
                    CONVERT(NVARCHAR, lc.closedAt, 127) AS closedAt,
                    CONVERT(NVARCHAR, lc.created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, lc.updated_at, 127) AS updated_at,
                    (SELECT noteId, authorRole, noteText,
                            CONVERT(NVARCHAR, created_At, 127) AS created_At
                     FROM dbo.legalCaseNotes WHERE caseId = lc.caseId
                     ORDER BY created_At
                     FOR JSON PATH) AS notes
             FROM legalCases lc
             WHERE lc.caseId = @caseId AND lc.companyId = @companyId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    -- ── update_status ─────────────────────────────────────────
    ELSE IF @action = 'update_status'
    BEGIN
        DECLARE @newCaseStatus NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.case[0].caseStatus')
        DECLARE @caseStage     NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.case[0].caseStage')
        DECLARE @statusNote    NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.case[0].statusNote')

        UPDATE legalCases SET
            caseStatus  = ISNULL(@newCaseStatus, caseStatus),
            caseStage   = ISNULL(@caseStage, caseStage),
            statusNote  = ISNULL(@statusNote, statusNote),
            updated_at  = GETUTCDATE()
        WHERE caseId = @caseId AND companyId = @companyId

        DECLARE @updateLenderUserId INT
        SELECT @updateLenderUserId = lenderUserId FROM legalCases WHERE caseId = @caseId

        SELECT (
            SELECT @caseId AS caseId, @newCaseStatus AS caseStatus,
                   @statusNote AS statusNote, @updateLenderUserId AS lenderUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── add_case_note ─────────────────────────────────────────
    ELSE IF @action = 'add_case_note'
    BEGIN
        DECLARE @noteAuthorClientId INT          = JSON_VALUE(@pjsonfile, '$.case[0].authorClientId')
        DECLARE @noteAuthorRole     NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.case[0].authorRole')
        DECLARE @noteText           NVARCHAR(MAX)= JSON_VALUE(@pjsonfile, '$.case[0].noteText')

        INSERT INTO legalCaseNotes (caseId, authorClientId, authorRole, noteText)
        VALUES (@caseId, @noteAuthorClientId, @noteAuthorRole, @noteText)

        SELECT (
            SELECT SCOPE_IDENTITY() AS noteId, @caseId AS caseId,
                   @noteAuthorRole AS authorRole, @noteText AS noteText,
                   CONVERT(NVARCHAR, GETUTCDATE(), 127) AS created_At
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── close_case ────────────────────────────────────────────
    ELSE IF @action = 'close_case'
    BEGIN
        DECLARE @closeNote       NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.case[0].statusNote')
        DECLARE @recoveredAmount DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.case[0].recoveredAmount')

        UPDATE legalCases SET
            caseStatus       = 'closed',
            recoveredAmount  = ISNULL(@recoveredAmount, recoveredAmount),
            statusNote       = ISNULL(@closeNote, statusNote),
            closedAt         = GETUTCDATE(),
            updated_at       = GETUTCDATE()
        WHERE caseId = @caseId AND companyId = @companyId

        DECLARE @closeLenderUserId INT
        DECLARE @closeLawyerUserId INT
        SELECT @closeLenderUserId = lenderUserId, @closeLawyerUserId = lawyerUserId
        FROM legalCases WHERE caseId = @caseId

        SELECT (
            SELECT @caseId AS caseId, 'closed' AS caseStatus,
                   @recoveredAmount AS recoveredAmount,
                   @closeLenderUserId AS lenderUserId, @closeLawyerUserId AS lawyerUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    -- ── embargo_executed ──────────────────────────────────────
    ELSE IF @action = 'embargo_executed'
    BEGIN
        DECLARE @embargoRecovered DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.case[0].recoveredAmount')
        DECLARE @embargoNote      NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.case[0].statusNote')

        UPDATE legalCases SET
            caseStatus         = 'embargo',
            recoveredAmount    = ISNULL(@embargoRecovered, recoveredAmount),
            statusNote         = ISNULL(@embargoNote, statusNote),
            embargoExecutedAt  = GETUTCDATE(),
            updated_at         = GETUTCDATE()
        WHERE caseId = @caseId AND companyId = @companyId

        INSERT INTO legalCaseNotes (caseId, authorClientId, authorRole, noteText)
        VALUES (@caseId, @clientId, 'system',
                'Embargo ejecutado. Monto recuperado: $' + CAST(ISNULL(@embargoRecovered, 0) AS NVARCHAR))

        DECLARE @embargoLenderUserId INT
        DECLARE @embargoLawyerUserId INT
        SELECT @embargoLenderUserId = lenderUserId, @embargoLawyerUserId = lawyerUserId
        FROM legalCases WHERE caseId = @caseId

        SELECT (
            SELECT @caseId AS caseId, 'embargo' AS caseStatus,
                   @embargoRecovered AS recoveredAmount,
                   @embargoLenderUserId AS lenderUserId, @embargoLawyerUserId AS lawyerUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
