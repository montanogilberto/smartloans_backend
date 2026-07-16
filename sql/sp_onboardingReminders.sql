-- ============================================================
-- Onboarding completion reminders — one-time-per-client tracking
-- Table:    onboardingReminders
-- SP:       sp_onboardingReminders  (action = 'getIncomplete' | 'markReminded')
-- Run this script once in your Azure SQL database
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'onboardingReminders')
CREATE TABLE [dbo].[onboardingReminders] (
    reminderId    INT IDENTITY PRIMARY KEY,
    clientId      INT NOT NULL,
    companyId     INT NOT NULL,
    missingSteps  NVARCHAR(500) NOT NULL,
    sentAt        DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_onboardingReminders_client UNIQUE (clientId, companyId)
)
GO

-- ============================================================
-- sp_onboardingReminders  (action = 'getIncomplete' | 'markReminded')
-- ============================================================
IF OBJECT_ID('dbo.sp_onboardingReminders', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_onboardingReminders;
GO

CREATE PROCEDURE [dbo].[sp_onboardingReminders]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action       NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.onboardingReminders[0].action')
        DECLARE @companyId    INT           = JSON_VALUE(@pjsonfile, '$.onboardingReminders[0].companyId')
        DECLARE @clientId     INT           = JSON_VALUE(@pjsonfile, '$.onboardingReminders[0].clientId')
        DECLARE @missingSteps NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.onboardingReminders[0].missingSteps')

        -- Returns every client in the company who hasn't already been
        -- reminded (LEFT JOIN ... IS NULL), with the raw per-step
        -- completion flags. The caller decides what "missing" text to
        -- show and whether the client counts as complete overall.
        IF @action = 'getIncomplete'
        BEGIN
            SELECT ISNULL(
                (SELECT c.clientId,
                        CASE WHEN c.qrBlobUrl IS NULL OR c.qrBlobUrl = '' THEN 0 ELSE 1 END AS hasQr,
                        CASE WHEN f.id_front_image_blob_url IS NULL OR f.id_back_image_blob_url IS NULL THEN 0 ELSE 1 END AS hasDocuments,
                        CASE WHEN f.is_verified = 1 THEN 1 ELSE 0 END AS isVerified,
                        CASE WHEN f.contract_accepted = 1 AND f.pagare_accepted = 1 THEN 1 ELSE 0 END AS hasContract,
                        CASE WHEN sca.hasExternalAccount = 1 THEN 1 ELSE 0 END AS hasBankAccount,
                        CASE WHEN spm.stripePaymentMethodId IS NULL THEN 0 ELSE 1 END AS hasSavedCard
                 FROM [dbo].[clients] c
                 LEFT JOIN [dbo].[clientFaceRecognitions] f ON f.clientId = c.clientId AND f.companyId = c.companyId
                 LEFT JOIN [dbo].[stripeConnectedAccounts] sca ON sca.clientId = c.clientId AND sca.companyId = c.companyId
                 LEFT JOIN [dbo].[savedPaymentMethods] spm ON spm.clientId = c.clientId AND spm.companyId = c.companyId
                 LEFT JOIN [dbo].[onboardingReminders] r ON r.clientId = c.clientId AND r.companyId = c.companyId
                 WHERE c.companyId = @companyId AND r.reminderId IS NULL
                 FOR JSON PATH, ROOT('clients')),
                '{"clients":[]}'
            ) AS [jsonResult]
        END

        -- Idempotent: the UNIQUE constraint means a client can only ever
        -- be marked once, matching the "remind once, then stop" behavior.
        ELSE IF @action = 'markReminded'
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[onboardingReminders] WHERE clientId = @clientId AND companyId = @companyId)
            BEGIN
                INSERT INTO [dbo].[onboardingReminders] (clientId, companyId, missingSteps)
                VALUES (@clientId, @companyId, @missingSteps)
            END

            SELECT '{"message":"marked"}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
