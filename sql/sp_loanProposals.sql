-- ============================================================
-- sp_loanProposals  (action 1=create, 2=update, 3=delete)
-- ============================================================
-- Required table:
-- CREATE TABLE [dbo].[loanProposals] (
--   proposalId      INT IDENTITY PRIMARY KEY,
--   companyId       INT NOT NULL,
--   lenderId        INT NOT NULL,
--   borrowerId      INT NOT NULL,
--   requestedAmount DECIMAL(18,2) NOT NULL,
--   proposedRate    DECIMAL(5,2) NOT NULL,
--   termMonths      INT NOT NULL,
--   status          NVARCHAR(20) NOT NULL DEFAULT 'pending',
--                   -- pending | accepted | rejected | expired | cancelled
--   lenderNote      NVARCHAR(500) NULL,
--   borrowerNote    NVARCHAR(500) NULL,
--   pushNotificationId INT NULL,
--   respondedAt     DATETIME2 NULL,
--   expiresAt       DATETIME2 NULL,
--   created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
--   updated_at      DATETIME2 NULL,
-- )
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
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[loanProposals]
                    WHERE proposalId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (accept / reject / cancel)
        BEGIN
            UPDATE [dbo].[loanProposals]
            SET status       = ISNULL(@status, status),
                lenderNote   = ISNULL(@lenderNote, lenderNote),
                respondedAt  = ISNULL(@respondedAt, respondedAt),
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
