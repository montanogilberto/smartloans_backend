-- ============================================================
-- sp_loanOffers  (action 1=create, 2=update/close, 3=delete)
-- ============================================================
-- Required table:
-- CREATE TABLE [dbo].[loanOffers] (
--   offerId         INT IDENTITY PRIMARY KEY,
--   companyId       INT NOT NULL,
--   lenderId        INT NOT NULL,           -- clientId of the lender
--   availableCapital DECIMAL(18,2) NOT NULL,
--   minRate         DECIMAL(5,2) NOT NULL,
--   maxRate         DECIMAL(5,2) NOT NULL,
--   minTermMonths   INT NOT NULL DEFAULT 1,
--   maxTermMonths   INT NOT NULL DEFAULT 24,
--   description     NVARCHAR(500) NULL,
--   isActive        BIT NOT NULL DEFAULT 1,
--   expiresAt       DATETIME2 NULL,
--   created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
-- )
-- ============================================================
IF OBJECT_ID('dbo.sp_loanOffers', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loanOffers;
GO

CREATE PROCEDURE [dbo].[sp_loanOffers]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action         INT            = JSON_VALUE(@pjsonfile, '$.loanOffers[0].action')
        DECLARE @offerId        INT            = JSON_VALUE(@pjsonfile, '$.loanOffers[0].offerId')
        DECLARE @companyId      INT            = JSON_VALUE(@pjsonfile, '$.loanOffers[0].companyId')
        DECLARE @lenderId       INT            = JSON_VALUE(@pjsonfile, '$.loanOffers[0].lenderId')
        DECLARE @availableCapital DECIMAL(18,2)= JSON_VALUE(@pjsonfile, '$.loanOffers[0].availableCapital')
        DECLARE @minRate        DECIMAL(5,2)   = JSON_VALUE(@pjsonfile, '$.loanOffers[0].minRate')
        DECLARE @maxRate        DECIMAL(5,2)   = JSON_VALUE(@pjsonfile, '$.loanOffers[0].maxRate')
        DECLARE @minTermMonths  INT            = ISNULL(JSON_VALUE(@pjsonfile, '$.loanOffers[0].minTermMonths'), 1)
        DECLARE @maxTermMonths  INT            = ISNULL(JSON_VALUE(@pjsonfile, '$.loanOffers[0].maxTermMonths'), 24)
        DECLARE @description    NVARCHAR(500)  = JSON_VALUE(@pjsonfile, '$.loanOffers[0].description')
        DECLARE @isActive       BIT            = ISNULL(JSON_VALUE(@pjsonfile, '$.loanOffers[0].isActive'), 1)
        DECLARE @expiresAt      DATETIME2      = JSON_VALUE(@pjsonfile, '$.loanOffers[0].expiresAt')

        IF @action = 1 -- CREATE
        BEGIN
            INSERT INTO [dbo].[loanOffers]
                (companyId, lenderId, availableCapital, minRate, maxRate,
                 minTermMonths, maxTermMonths, description, isActive, expiresAt)
            VALUES
                (@companyId, @lenderId, @availableCapital, @minRate, @maxRate,
                 @minTermMonths, @maxTermMonths, @description, @isActive, @expiresAt)

            SELECT (SELECT TOP 1 * FROM [dbo].[loanOffers]
                    WHERE offerId = SCOPE_IDENTITY() FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE / CLOSE
        BEGIN
            UPDATE [dbo].[loanOffers]
            SET isActive    = ISNULL(@isActive, isActive),
                description = ISNULL(@description, description)
            WHERE offerId = @offerId AND companyId = @companyId

            SELECT '{"message":"updated","offerId":' + CAST(@offerId AS NVARCHAR) + '}' AS [jsonResult]
        END

        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE FROM [dbo].[loanOffers] WHERE offerId = @offerId AND companyId = @companyId
            SELECT '{"message":"deleted","offerId":' + CAST(@offerId AS NVARCHAR) + '}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_loanOffers_all  — list active offers by companyId
-- ============================================================
IF OBJECT_ID('dbo.sp_loanOffers_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loanOffers_all;
GO

CREATE PROCEDURE [dbo].[sp_loanOffers_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.loanOffers[0].companyId')
        DECLARE @isActive  BIT = JSON_VALUE(@pjsonfile, '$.loanOffers[0].isActive')

        SELECT ISNULL(
            (SELECT offerId, companyId, lenderId, availableCapital, minRate, maxRate,
                    minTermMonths, maxTermMonths, description, isActive,
                    CONVERT(NVARCHAR, expiresAt, 127) AS expiresAt,
                    CONVERT(NVARCHAR, created_At, 127) AS created_At
             FROM [dbo].[loanOffers]
             WHERE companyId = @companyId
               AND (@isActive IS NULL OR isActive = @isActive)
             ORDER BY created_At DESC
             FOR JSON PATH, ROOT('loanOffers')),
            '{"loanOffers":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
-- sp_loanOffers_one
-- ============================================================
IF OBJECT_ID('dbo.sp_loanOffers_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loanOffers_one;
GO

CREATE PROCEDURE [dbo].[sp_loanOffers_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @offerId INT = JSON_VALUE(@pjsonfile, '$.loanOffers[0].offerId')

        SELECT ISNULL(
            (SELECT TOP 1 * FROM [dbo].[loanOffers]
             WHERE offerId = @offerId
             FOR JSON PATH, ROOT('loanOffers')),
            '{"loanOffers":[]}'
        ) AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
