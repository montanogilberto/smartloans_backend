-- ============================================================
-- Required table:
-- CREATE TABLE [dbo].[clientDashboards] (
--   clientDashboardId  INT IDENTITY PRIMARY KEY,
--   companyId          INT NOT NULL,
--   clientId           INT NOT NULL,
--   availableCredit    DECIMAL(18,2) NULL,
--   activeLoanBalance  DECIMAL(18,2) NULL,
--   nextPaymentAmount  DECIMAL(18,2) NULL,
--   nextPaymentDate    DATETIME2 NULL,
--   activityDate       DATETIME2 NULL,
--   activityType       NVARCHAR(50) NULL,
--   description        NVARCHAR(500) NULL,
--   amount             DECIMAL(18,2) NULL,
--   loanNumber         NVARCHAR(50) NULL,
--   loanAmount         DECIMAL(18,2) NULL,
--   remainingBalance   DECIMAL(18,2) NULL,
--   status             NVARCHAR(30) NULL,
--   created_At         DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
--   updated_at         DATETIME2 NULL,
-- )
-- ============================================================

-- ============================================================
-- sp_clientDashboards  (action 1=create, 2=update, 3=delete)
-- ============================================================
IF OBJECT_ID('dbo.sp_clientDashboards', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_clientDashboards;
GO

CREATE PROCEDURE [dbo].[sp_clientDashboards]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action           INT           = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].action')
        DECLARE @clientDashboardId INT          = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].clientDashboardId')
        DECLARE @companyId        INT           = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].companyId')
        DECLARE @clientId         INT           = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].clientId')
        DECLARE @availableCredit  DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].availableCredit')
        DECLARE @activeLoanBalance DECIMAL(18,2)= JSON_VALUE(@pjsonfile, '$.clientDashboards[0].activeLoanBalance')
        DECLARE @nextPaymentAmount DECIMAL(18,2)= JSON_VALUE(@pjsonfile, '$.clientDashboards[0].nextPaymentAmount')
        DECLARE @nextPaymentDate  DATETIME2     = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].nextPaymentDate')
        DECLARE @activityDate     DATETIME2     = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].activityDate')
        DECLARE @activityType     NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].activityType')
        DECLARE @description      NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].description')
        DECLARE @amount           DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].amount')
        DECLARE @loanNumber       NVARCHAR(50)  = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].loanNumber')
        DECLARE @loanAmount       DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].loanAmount')
        DECLARE @remainingBalance DECIMAL(18,2) = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].remainingBalance')
        DECLARE @status           NVARCHAR(30)  = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].status')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[clientDashboards]
                (companyId, clientId, availableCredit, activeLoanBalance, nextPaymentAmount,
                 nextPaymentDate, activityDate, activityType, description, amount,
                 loanNumber, loanAmount, remainingBalance, status)
            VALUES
                (@companyId, @clientId, @availableCredit, @activeLoanBalance, @nextPaymentAmount,
                 @nextPaymentDate, @activityDate, @activityType, @description, @amount,
                 @loanNumber, @loanAmount, @remainingBalance, @status)

            SELECT (SELECT TOP 1 clientDashboardId, companyId, clientId, availableCredit,
                           activeLoanBalance, nextPaymentAmount,
                           CONVERT(NVARCHAR, nextPaymentDate, 127) AS nextPaymentDate,
                           CONVERT(NVARCHAR, activityDate, 127) AS activityDate,
                           activityType, description, amount, loanNumber, loanAmount,
                           remainingBalance, status,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[clientDashboards]
                    WHERE clientDashboardId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE
        BEGIN
            UPDATE [dbo].[clientDashboards]
            SET availableCredit   = ISNULL(@availableCredit, availableCredit),
                activeLoanBalance = ISNULL(@activeLoanBalance, activeLoanBalance),
                nextPaymentAmount = ISNULL(@nextPaymentAmount, nextPaymentAmount),
                nextPaymentDate   = ISNULL(@nextPaymentDate, nextPaymentDate),
                activityDate      = ISNULL(@activityDate, activityDate),
                activityType      = ISNULL(@activityType, activityType),
                description       = ISNULL(@description, description),
                amount            = ISNULL(@amount, amount),
                loanNumber        = ISNULL(@loanNumber, loanNumber),
                loanAmount        = ISNULL(@loanAmount, loanAmount),
                remainingBalance  = ISNULL(@remainingBalance, remainingBalance),
                status            = ISNULL(@status, status),
                updated_at        = GETUTCDATE()
            WHERE clientDashboardId = @clientDashboardId AND companyId = @companyId

            SELECT '{"message":"updated","clientDashboardId":' + CAST(@clientDashboardId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[clientDashboards]
            WHERE clientDashboardId = @clientDashboardId AND companyId = @companyId

            SELECT '{"message":"deleted","clientDashboardId":' + CAST(@clientDashboardId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_clientDashboards_all  — list dashboard entries by companyId + clientId
-- ============================================================
IF OBJECT_ID('dbo.sp_clientDashboards_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_clientDashboards_all;
GO

CREATE PROCEDURE [dbo].[sp_clientDashboards_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].companyId')
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.clientDashboards[0].clientId')

        SELECT ISNULL(
            (SELECT clientDashboardId, companyId, clientId, availableCredit,
                    activeLoanBalance, nextPaymentAmount,
                    CONVERT(NVARCHAR, nextPaymentDate, 127) AS nextPaymentDate,
                    CONVERT(NVARCHAR, activityDate, 127) AS activityDate,
                    activityType, description, amount, loanNumber, loanAmount,
                    remainingBalance, status,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At,
                    CONVERT(NVARCHAR, updated_at, 127) AS updated_at
             FROM [dbo].[clientDashboards]
             WHERE companyId = @companyId
               AND (@clientId IS NULL OR clientId = @clientId)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('clientDashboards')),
            '{"clientDashboards":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
