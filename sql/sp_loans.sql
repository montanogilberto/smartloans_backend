-- ============================================================
-- Required table:
-- CREATE TABLE [dbo].[loans] (
--   loanId               INT IDENTITY PRIMARY KEY,
--   companyId            INT NOT NULL,
--   loanNumber           NVARCHAR(50) NOT NULL,
--   clientId             INT NOT NULL,
--   principalAmount      DECIMAL(18,2) NOT NULL,
--   interestRate         DECIMAL(5,2) NOT NULL,
--   termMonths           INT NOT NULL,
--   paymentFrequency     NVARCHAR(20) NOT NULL DEFAULT 'monthly',
--   approvedAmount       DECIMAL(18,2) NULL,
--   totalRepaymentAmount DECIMAL(18,2) NULL,
--   disbursementDate     DATETIME2 NULL,
--   maturityDate         DATETIME2 NULL,
--   loanStatus           NVARCHAR(30) NOT NULL DEFAULT 'pending',
--   notes                NVARCHAR(MAX) NULL,
--   created_At           DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
--   updated_at           DATETIME2 NULL,
-- )
-- ============================================================

-- ============================================================
-- sp_loans  (action 1=create, 2=update, 3=delete)
-- ============================================================
IF OBJECT_ID('dbo.sp_loans', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loans;
GO

CREATE PROCEDURE [dbo].[sp_loans]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action              INT            = JSON_VALUE(@pjsonfile, '$.loans[0].action')
        DECLARE @loanId              INT            = JSON_VALUE(@pjsonfile, '$.loans[0].loanId')
        DECLARE @companyId           INT            = JSON_VALUE(@pjsonfile, '$.loans[0].companyId')
        DECLARE @loanNumber          NVARCHAR(50)   = JSON_VALUE(@pjsonfile, '$.loans[0].loanNumber')
        DECLARE @clientId            INT            = JSON_VALUE(@pjsonfile, '$.loans[0].clientId')
        DECLARE @principalAmount     DECIMAL(18,2)  = JSON_VALUE(@pjsonfile, '$.loans[0].principalAmount')
        DECLARE @interestRate        DECIMAL(5,2)   = JSON_VALUE(@pjsonfile, '$.loans[0].interestRate')
        DECLARE @termMonths          INT            = JSON_VALUE(@pjsonfile, '$.loans[0].termMonths')
        DECLARE @paymentFrequency    NVARCHAR(20)   = ISNULL(JSON_VALUE(@pjsonfile, '$.loans[0].paymentFrequency'), 'monthly')
        DECLARE @approvedAmount      DECIMAL(18,2)  = JSON_VALUE(@pjsonfile, '$.loans[0].approvedAmount')
        DECLARE @totalRepaymentAmount DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.loans[0].totalRepaymentAmount')
        DECLARE @disbursementDate    DATETIME2      = JSON_VALUE(@pjsonfile, '$.loans[0].disbursementDate')
        DECLARE @maturityDate        DATETIME2      = JSON_VALUE(@pjsonfile, '$.loans[0].maturityDate')
        DECLARE @loanStatus          NVARCHAR(30)   = ISNULL(JSON_VALUE(@pjsonfile, '$.loans[0].loanStatus'), 'pending')
        DECLARE @notes               NVARCHAR(MAX)  = JSON_VALUE(@pjsonfile, '$.loans[0].notes')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[loans]
                (companyId, loanNumber, clientId, principalAmount, interestRate, termMonths,
                 paymentFrequency, approvedAmount, totalRepaymentAmount, disbursementDate,
                 maturityDate, loanStatus, notes)
            VALUES
                (@companyId, @loanNumber, @clientId, @principalAmount, @interestRate, @termMonths,
                 @paymentFrequency, @approvedAmount, @totalRepaymentAmount, @disbursementDate,
                 @maturityDate, @loanStatus, @notes)

            SELECT (SELECT TOP 1 loanId, companyId, loanNumber, clientId, principalAmount,
                           interestRate, termMonths, paymentFrequency, approvedAmount,
                           totalRepaymentAmount,
                           CONVERT(NVARCHAR, disbursementDate, 127) AS disbursementDate,
                           CONVERT(NVARCHAR, maturityDate, 127) AS maturityDate,
                           loanStatus, notes,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At,
                           CONVERT(NVARCHAR, updated_at, 127) AS updated_at
                    FROM [dbo].[loans]
                    WHERE loanId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE
        BEGIN
            UPDATE [dbo].[loans]
            SET loanNumber           = ISNULL(@loanNumber, loanNumber),
                principalAmount      = ISNULL(@principalAmount, principalAmount),
                interestRate         = ISNULL(@interestRate, interestRate),
                termMonths           = ISNULL(@termMonths, termMonths),
                paymentFrequency     = ISNULL(@paymentFrequency, paymentFrequency),
                approvedAmount       = ISNULL(@approvedAmount, approvedAmount),
                totalRepaymentAmount = ISNULL(@totalRepaymentAmount, totalRepaymentAmount),
                disbursementDate     = ISNULL(@disbursementDate, disbursementDate),
                maturityDate         = ISNULL(@maturityDate, maturityDate),
                loanStatus           = ISNULL(@loanStatus, loanStatus),
                notes                = ISNULL(@notes, notes),
                updated_at           = GETUTCDATE()
            WHERE loanId = @loanId AND companyId = @companyId

            SELECT '{"message":"updated","loanId":' + CAST(@loanId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[loans] WHERE loanId = @loanId AND companyId = @companyId
            SELECT '{"message":"deleted","loanId":' + CAST(@loanId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_loans_all  — list loans by companyId (optionally filtered by loanNumber)
-- ============================================================
IF OBJECT_ID('dbo.sp_loans_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loans_all;
GO

CREATE PROCEDURE [dbo].[sp_loans_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId  INT          = JSON_VALUE(@pjsonfile, '$.loans[0].companyId')
        DECLARE @loanNumber NVARCHAR(50) = JSON_VALUE(@pjsonfile, '$.loans[0].loanNumber')

        SELECT ISNULL(
            (SELECT loanId, companyId, loanNumber, clientId, principalAmount,
                    interestRate, termMonths, paymentFrequency, approvedAmount,
                    totalRepaymentAmount,
                    CONVERT(NVARCHAR, disbursementDate, 127) AS disbursementDate,
                    CONVERT(NVARCHAR, maturityDate, 127) AS maturityDate,
                    loanStatus, notes,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM [dbo].[loans]
             WHERE companyId = @companyId
               AND (@loanNumber IS NULL OR loanNumber LIKE '%' + @loanNumber + '%')
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('loans')),
            '{"loans":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_loans_one  — get single loan by loanId
-- ============================================================
IF OBJECT_ID('dbo.sp_loans_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loans_one;
GO

CREATE PROCEDURE [dbo].[sp_loans_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @loanId    INT = JSON_VALUE(@pjsonfile, '$.loans[0].loanId')
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.loans[0].companyId')

        SELECT ISNULL(
            (SELECT TOP 1 loanId, companyId, loanNumber, clientId, principalAmount,
                          interestRate, termMonths, paymentFrequency, approvedAmount,
                          totalRepaymentAmount,
                          CONVERT(NVARCHAR, disbursementDate, 127) AS disbursementDate,
                          CONVERT(NVARCHAR, maturityDate, 127) AS maturityDate,
                          loanStatus, notes,
                          CONVERT(NVARCHAR, created_At, 127) AS created_At,
                          CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM [dbo].[loans]
             WHERE loanId = @loanId AND companyId = @companyId
             FOR JSON PATH, ROOT('loans')),
            '{"loans":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
