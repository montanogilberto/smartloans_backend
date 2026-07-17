SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- ============================================================
-- Registration wizard completion — new columns + reminders
--
-- CreateAccount.tsx's 4-step wizard (Cuenta/Perfil/Verificar/Acceso) only
-- ever persisted steps 1 (dbo.users row) and 4 (dbo.userCompanies row).
-- Steps 2 (Perfil) and 3 (Verificar) were computed client-side only and
-- lost on reload, so a returning contact could never resume partway or be
-- reliably told "you're fully registered" vs "you're not done yet".
--
-- These columns give steps 2 & 3 real, cross-session state. sp_checkContact
-- (v5) reads them back as stepProfile/stepVerify/stepAccess/regComplete.
--
-- Table + SP below mirror the onboardingReminders pattern (loan-onboarding
-- reminders) — one-time-per-user push/email/whatsapp/sms nudge, tracked so
-- nobody is reminded twice.
-- ============================================================

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'appProfile')
    ALTER TABLE [dbo].[users] ADD [appProfile] VARCHAR(20) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'enabledModules')
    ALTER TABLE [dbo].[users] ADD [enabledModules] NVARCHAR(MAX) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.users') AND name = 'identityVerified')
    ALTER TABLE [dbo].[users] ADD [identityVerified] BIT NOT NULL CONSTRAINT DF_users_identityVerified DEFAULT (0);
GO

-- ============================================================
-- Table: registrationReminders — one row per user ever reminded
-- ============================================================
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'registrationReminders')
CREATE TABLE [dbo].[registrationReminders] (
    reminderId    INT IDENTITY PRIMARY KEY,
    userId        INT NOT NULL,
    missingSteps  NVARCHAR(500) NOT NULL,
    sentAt        DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_registrationReminders_user UNIQUE (userId)
)
GO

-- ============================================================
-- sp_registrationReminders  (action = 'getIncomplete' | 'markReminded')
-- ============================================================
IF OBJECT_ID('dbo.sp_registrationReminders', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_registrationReminders;
GO

CREATE PROCEDURE [dbo].[sp_registrationReminders]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action       NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.registrationReminders[0].action')
        DECLARE @userId       INT           = JSON_VALUE(@pjsonfile, '$.registrationReminders[0].userId')
        DECLARE @missingSteps NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.registrationReminders[0].missingSteps')

        -- Every user with an incomplete registration who hasn't already
        -- been reminded (LEFT JOIN ... IS NULL). Caller decides the
        -- missing-steps text and how/whether to notify.
        IF @action = 'getIncomplete'
        BEGIN
            SELECT ISNULL(
                (SELECT u.userId,
                        u.email,
                        u.cellphone,
                        CASE WHEN u.appProfile IS NULL THEN 0 ELSE 1 END AS hasProfile,
                        CASE WHEN u.identityVerified = 1 THEN 1 ELSE 0 END AS isVerified,
                        CASE WHEN uc.userId IS NULL THEN 0 ELSE 1 END AS hasAccess,
                        uc.companyId AS companyId
                 FROM [dbo].[users] u
                 OUTER APPLY (SELECT TOP 1 userId, companyId FROM [dbo].[userCompanies] WHERE userId = u.userId) uc
                 LEFT JOIN [dbo].[registrationReminders] r ON r.userId = u.userId
                 WHERE r.reminderId IS NULL
                   AND (u.appProfile IS NULL OR u.identityVerified = 0 OR uc.userId IS NULL)
                 FOR JSON PATH, ROOT('users')),
                '{"users":[]}'
            ) AS [jsonResult]
        END

        -- Idempotent: UNIQUE(userId) means a user can only ever be marked
        -- once — remind once, then stop (staff can still nudge manually).
        ELSE IF @action = 'markReminded'
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[registrationReminders] WHERE userId = @userId)
            BEGIN
                INSERT INTO [dbo].[registrationReminders] (userId, missingSteps)
                VALUES (@userId, @missingSteps)
            END

            SELECT '{"message":"marked"}' AS [jsonResult]
        END
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
