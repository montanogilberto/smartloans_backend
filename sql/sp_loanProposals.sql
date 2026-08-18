-- ============================================================
-- sp_loanProposals  (action 1=create, 2=update, 3=delete)
-- ============================================================

-- ── Table: loanProposals_status (lookup / catalog) ──────────
-- Created BEFORE loanProposals so the FK below can reference it.
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'loanProposals_status')
CREATE TABLE [dbo].[loanProposals_status] (
    statusCode   NVARCHAR(20)   NOT NULL PRIMARY KEY,
    sortOrder    INT            NOT NULL,
    description  NVARCHAR(100)  NULL,
    isTerminal   BIT            NOT NULL DEFAULT 0   -- 1 = no further transitions
)
GO

-- Seed the catalog values (idempotent)
MERGE [dbo].[loanProposals_status] AS t
USING (VALUES
    ('pending',   1, 'Awaiting the counterparty response', 0),
    ('accepted',  2, 'Proposal accepted, loan proceeds',   1),
    ('rejected',  3, 'Proposal declined',                  1),
    ('expired',   4, 'Lapsed past expiresAt',              1),
    ('cancelled', 5, 'Withdrawn by the initiator',         1),
    -- Lender proposed different terms (single-cycle negotiation, no loop):
    -- borrower can only accept (-> pending, terms already updated, ready for
    -- the lender to approve/fund) or reject (terminal) -- never counter back.
    ('countered', 6, 'Lender proposed different terms',    0)
) AS s (statusCode, sortOrder, description, isTerminal)
ON t.statusCode = s.statusCode
WHEN NOT MATCHED THEN
    INSERT (statusCode, sortOrder, description, isTerminal)
    VALUES (s.statusCode, s.sortOrder, s.description, s.isTerminal);
GO

-- ── Table: loanProposals ────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'loanProposals')
CREATE TABLE [dbo].[loanProposals] (
    proposalId          INT IDENTITY PRIMARY KEY,
    companyId           INT            NOT NULL,
    lenderId            INT            NOT NULL,
    borrowerId          INT            NOT NULL,
    requestedAmount     DECIMAL(18,2)  NOT NULL,
    proposedRate        DECIMAL(5,2)   NOT NULL,
    termMonths          INT            NOT NULL,
    status              NVARCHAR(20)   NOT NULL DEFAULT 'pending',
                        -- pending | accepted | rejected | expired | cancelled | countered
    lenderNote          NVARCHAR(500)  NULL,
    borrowerNote        NVARCHAR(500)  NULL,
    pushNotificationId  INT            NULL,
    respondedAt         DATETIME2      NULL,
    expiresAt           DATETIME2      NULL,
    -- requestedAmount/proposedRate/termMonths above are the BORROWER's
    -- original ask and are never overwritten -- a permanent historical
    -- record (negotiation-outcome data, e.g. for a future model on what
    -- terms get accepted). counteredAt/Amount/Rate/TermMonths below record
    -- the lender's counter-offer separately, if any -- also never
    -- overwritten once set, so the full negotiation (ask -> counter ->
    -- outcome) stays reconstructable from one row.
    counteredAmount     DECIMAL(18,2)  NULL,
    counteredRate       DECIMAL(5,2)   NULL,
    counteredTermMonths INT            NULL,
    counteredAt         DATETIME2      NULL,
    created_At          DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at          DATETIME2      NULL
)
GO

-- Existing production table predates these columns (idempotent ALTER).
IF COL_LENGTH('dbo.loanProposals', 'counteredAmount') IS NULL
    ALTER TABLE [dbo].[loanProposals] ADD counteredAmount DECIMAL(18,2) NULL;
GO
IF COL_LENGTH('dbo.loanProposals', 'counteredRate') IS NULL
    ALTER TABLE [dbo].[loanProposals] ADD counteredRate DECIMAL(5,2) NULL;
GO
IF COL_LENGTH('dbo.loanProposals', 'counteredTermMonths') IS NULL
    ALTER TABLE [dbo].[loanProposals] ADD counteredTermMonths INT NULL;
GO
IF COL_LENGTH('dbo.loanProposals', 'counteredAt') IS NULL
    ALTER TABLE [dbo].[loanProposals] ADD counteredAt DATETIME2 NULL;
GO

-- Indexes matching the read patterns in sp_loanProposals_all / sp_creditScore_data
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_loanProposals_company_lender')
    CREATE INDEX IX_loanProposals_company_lender
        ON [dbo].[loanProposals] (companyId, lenderId, status) INCLUDE (created_At);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_loanProposals_company_borrower')
    CREATE INDEX IX_loanProposals_company_borrower
        ON [dbo].[loanProposals] (companyId, borrowerId, created_At);
GO

-- ── Relationship: loanProposals.status → loanProposals_status.statusCode
IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_loanProposals_status')
    ALTER TABLE [dbo].[loanProposals]
        ADD CONSTRAINT FK_loanProposals_status
        FOREIGN KEY (status) REFERENCES [dbo].[loanProposals_status] (statusCode);
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_loanProposals', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loanProposals;
GO

CREATE PROCEDURE [dbo].[sp_loanProposals]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].action')
        DECLARE @proposalId     INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].proposalId')
        DECLARE @companyId      INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].companyId')
        DECLARE @lenderId       INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].lenderId')
        DECLARE @borrowerId     INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].borrowerId')
        DECLARE @requestedAmount DECIMAL(18,2)  = JSON_VALUE(@pjsonfile, '$.loanProposals[0].requestedAmount')
        DECLARE @proposedRate   DECIMAL(5,2)    = JSON_VALUE(@pjsonfile, '$.loanProposals[0].proposedRate')
        DECLARE @termMonths     INT             = JSON_VALUE(@pjsonfile, '$.loanProposals[0].termMonths')
        DECLARE @status         NVARCHAR(20)    = ISNULL(JSON_VALUE(@pjsonfile, '$.loanProposals[0].status'), 'pending')
        DECLARE @borrowerNote   NVARCHAR(500)   = JSON_VALUE(@pjsonfile, '$.loanProposals[0].borrowerNote')
        DECLARE @lenderNote     NVARCHAR(500)   = JSON_VALUE(@pjsonfile, '$.loanProposals[0].lenderNote')
        DECLARE @pushNotificationId INT         = JSON_VALUE(@pjsonfile, '$.loanProposals[0].pushNotificationId')
        DECLARE @respondedAt    DATETIME2       = JSON_VALUE(@pjsonfile, '$.loanProposals[0].respondedAt')
        DECLARE @expiresAt      DATETIME2       = JSON_VALUE(@pjsonfile, '$.loanProposals[0].expiresAt')
        DECLARE @counteredAmount     DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.loanProposals[0].counteredAmount')
        DECLARE @counteredRate       DECIMAL(5,2)  = JSON_VALUE(@pjsonfile, '$.loanProposals[0].counteredRate')
        DECLARE @counteredTermMonths INT           = JSON_VALUE(@pjsonfile, '$.loanProposals[0].counteredTermMonths')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[loanProposals]
                (companyId, lenderId, borrowerId, requestedAmount, proposedRate, termMonths,
                 status, borrowerNote, lenderNote, pushNotificationId, expiresAt)
            VALUES
                (@companyId, @lenderId, @borrowerId, @requestedAmount, @proposedRate, @termMonths,
                 @status, @borrowerNote, @lenderNote, @pushNotificationId, @expiresAt)

            SELECT (SELECT TOP 1 proposalId, companyId, lenderId, borrowerId,
                           requestedAmount, proposedRate, termMonths, status,
                           borrowerNote, lenderNote,
                           counteredAmount, counteredRate, counteredTermMonths,
                           CONVERT(NVARCHAR, counteredAt, 127) AS counteredAt,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[loanProposals]
                    WHERE proposalId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (accept / reject / cancel / counter)
        BEGIN
            -- counteredAt is set server-side, once, the first time this row
            -- goes to 'countered' -- never overwritten on a later update
            -- (e.g. borrower accepting flips status back to 'pending' but
            -- must not erase when the counter itself happened).
            UPDATE [dbo].[loanProposals]
            SET status       = ISNULL(@status, status),
                lenderNote   = ISNULL(@lenderNote, lenderNote),
                respondedAt  = ISNULL(@respondedAt, respondedAt),
                counteredAmount     = ISNULL(@counteredAmount, counteredAmount),
                counteredRate       = ISNULL(@counteredRate, counteredRate),
                counteredTermMonths = ISNULL(@counteredTermMonths, counteredTermMonths),
                counteredAt = CASE WHEN @status = 'countered' AND counteredAt IS NULL
                                   THEN GETUTCDATE() ELSE counteredAt END,
                updated_at   = GETUTCDATE()
            WHERE proposalId = @proposalId

            SELECT '{"message":"updated","proposalId":' + CAST(@proposalId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[loanProposals] WHERE proposalId = @proposalId
            SELECT '{"message":"deleted","proposalId":' + CAST(@proposalId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_loanProposals_all
-- ============================================================
IF OBJECT_ID('dbo.sp_loanProposals_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loanProposals_all;
GO

CREATE PROCEDURE [dbo].[sp_loanProposals_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId  INT          = JSON_VALUE(@pjsonfile, '$.loanProposals[0].companyId')
        DECLARE @lenderId   INT          = JSON_VALUE(@pjsonfile, '$.loanProposals[0].lenderId')
        DECLARE @borrowerId INT          = JSON_VALUE(@pjsonfile, '$.loanProposals[0].borrowerId')
        DECLARE @status     NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.loanProposals[0].status')

        SELECT ISNULL(
            (SELECT proposalId, companyId, lenderId, borrowerId,
                    requestedAmount, proposedRate, termMonths, status,
                    borrowerNote, lenderNote, pushNotificationId,
                    counteredAmount, counteredRate, counteredTermMonths,
                    CONVERT(NVARCHAR, counteredAt, 127)  AS counteredAt,
                    CONVERT(NVARCHAR, respondedAt, 127) AS respondedAt,
                    CONVERT(NVARCHAR, expiresAt, 127)   AS expiresAt,
                    CONVERT(NVARCHAR, created_At, 127)  AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127)  AS updated_at
             FROM [dbo].[loanProposals]
             WHERE companyId = @companyId
               AND (@lenderId   IS NULL OR lenderId   = @lenderId)
               AND (@borrowerId IS NULL OR borrowerId = @borrowerId)
               AND (@status     IS NULL OR status     = @status)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('loanProposals')),
            '{"loanProposals":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_loanProposals_one
-- ============================================================
IF OBJECT_ID('dbo.sp_loanProposals_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loanProposals_one;
GO

CREATE PROCEDURE [dbo].[sp_loanProposals_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @proposalId INT = JSON_VALUE(@pjsonfile, '$.loanProposals[0].proposalId')

        SELECT ISNULL(
            (SELECT TOP 1 * FROM [dbo].[loanProposals]
             WHERE proposalId = @proposalId
             FOR JSON PATH, ROOT('loanProposals')),
            '{"loanProposals":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
