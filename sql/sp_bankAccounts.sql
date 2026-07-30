-- ============================================================
-- sp_bankAccounts  (action 1=create, 2=update/verify, 3=soft delete)
-- Verified CLABEs per client — SPEI payout/deposit destinations.
-- Banking-first Phase 1 (docs/payment-banking-first-redesign.md).
-- Spec: posgmo-factory/tests/prd_bankAccount.json
-- ============================================================

-- ── Table: bankAccounts ─────────────────────────────────────
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'bankAccounts')
CREATE TABLE [dbo].[bankAccounts] (
    bankAccountId       INT IDENTITY PRIMARY KEY,
    companyId           INT            NOT NULL,
    clientId            INT            NOT NULL,
    clabe               NVARCHAR(18)   NOT NULL,  -- LFPDPPP personal data: log only last 4
    bankCode            NVARCHAR(5)    NULL,      -- 3-digit ABM code from CLABE prefix
    bankName            NVARCHAR(100)  NULL,
    holderName          NVARCHAR(255)  NOT NULL,
    isVerified          BIT            NOT NULL DEFAULT 0,
    verificationMethod  NVARCHAR(20)   NULL,      -- micro_deposit | provider_link | manual
    -- Centavos amount of the pending micro-deposit; NULLed once verified so it
    -- cannot be replayed. Never returned by the list/one SPs.
    verificationCents   INT            NULL,
    verifiedAt          DATETIME2      NULL,
    isDefault           BIT            NOT NULL DEFAULT 0,
    isActive            BIT            NOT NULL DEFAULT 1,
    created_At          DATETIME2      NOT NULL DEFAULT GETUTCDATE(),
    updated_at          DATETIME2      NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_bankAccounts_client_clabe')
    CREATE UNIQUE INDEX UQ_bankAccounts_client_clabe
        ON [dbo].[bankAccounts] (clientId, clabe);
GO
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_bankAccounts_company_client')
    CREATE INDEX IX_bankAccounts_company_client
        ON [dbo].[bankAccounts] (companyId, clientId, isActive);
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_bankAccounts', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_bankAccounts;
GO

CREATE PROCEDURE [dbo].[sp_bankAccounts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action             INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].action')
        DECLARE @bankAccountId      INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankAccountId')
        DECLARE @companyId          INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].companyId')
        DECLARE @clientId           INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].clientId')
        DECLARE @clabe              NVARCHAR(18)   = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].clabe')
        DECLARE @bankCode           NVARCHAR(5)    = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankCode')
        DECLARE @bankName           NVARCHAR(100)  = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankName')
        DECLARE @holderName         NVARCHAR(255)  = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].holderName')
        DECLARE @isVerified         BIT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].isVerified')
        DECLARE @verificationMethod NVARCHAR(20)   = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].verificationMethod')
        DECLARE @verificationCents  INT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].verificationCents')
        DECLARE @isDefault          BIT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].isDefault')
        DECLARE @isActive           BIT            = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].isActive')

        IF @action = 1 -- CREATE (link)
        BEGIN
            -- First account for the client becomes the default automatically.
            DECLARE @firstForClient BIT =
                CASE WHEN EXISTS (SELECT 1 FROM [dbo].[bankAccounts]
                                  WHERE clientId = @clientId AND companyId = @companyId AND isActive = 1)
                     THEN 0 ELSE 1 END;

            INSERT INTO [dbo].[bankAccounts]
                (companyId, clientId, clabe, bankCode, bankName, holderName,
                 verificationMethod, verificationCents, isDefault)
            VALUES
                (@companyId, @clientId, @clabe, @bankCode, @bankName, @holderName,
                 ISNULL(@verificationMethod, 'micro_deposit'), @verificationCents,
                 ISNULL(@isDefault, @firstForClient))

            SELECT (SELECT TOP 1 bankAccountId, companyId, clientId,
                           RIGHT(clabe, 4) AS clabeLast4, bankCode, bankName, holderName,
                           isVerified, verificationMethod, isDefault,
                           CONVERT(NVARCHAR, created_At, 127) AS created_At
                    FROM [dbo].[bankAccounts]
                    WHERE bankAccountId = SCOPE_IDENTITY()
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 2 -- UPDATE (verify / set default / rename)
        BEGIN
            -- Making this account the default clears the previous one.
            IF @isDefault = 1
                UPDATE [dbo].[bankAccounts]
                SET isDefault = 0, updated_at = GETUTCDATE()
                WHERE clientId = (SELECT clientId FROM [dbo].[bankAccounts] WHERE bankAccountId = @bankAccountId)
                  AND companyId = @companyId AND bankAccountId <> @bankAccountId AND isDefault = 1;

            UPDATE [dbo].[bankAccounts]
            SET isVerified        = ISNULL(@isVerified, isVerified),
                verificationMethod = ISNULL(@verificationMethod, verificationMethod),
                -- On successful verification burn the micro-deposit code.
                verificationCents = CASE WHEN @isVerified = 1 THEN NULL ELSE verificationCents END,
                verifiedAt        = CASE WHEN @isVerified = 1 THEN GETUTCDATE() ELSE verifiedAt END,
                holderName        = ISNULL(@holderName, holderName),
                isDefault         = ISNULL(@isDefault, isDefault),
                isActive          = ISNULL(@isActive, isActive),
                updated_at        = GETUTCDATE()
            WHERE bankAccountId = @bankAccountId AND companyId = @companyId

            SELECT (SELECT TOP 1 bankAccountId, clientId, RIGHT(clabe, 4) AS clabeLast4,
                           bankName, isVerified, isDefault,
                           CONVERT(NVARCHAR, verifiedAt, 127) AS verifiedAt
                    FROM [dbo].[bankAccounts]
                    WHERE bankAccountId = @bankAccountId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END

        ELSE IF @action = 3 -- SOFT DELETE (audit trail keeps the row)
        BEGIN
            UPDATE [dbo].[bankAccounts]
            SET isActive = 0, isDefault = 0, updated_at = GETUTCDATE()
            WHERE bankAccountId = @bankAccountId AND companyId = @companyId

            SELECT '{"message":"deleted","bankAccountId":' + CAST(@bankAccountId AS NVARCHAR(20)) + '}' AS [jsonResult]
        END

        ELSE
            SELECT '{"error":"Invalid action"}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}') AS [jsonResult]
    END CATCH
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_bankAccounts_all', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_bankAccounts_all;
GO
CREATE PROCEDURE [dbo].[sp_bankAccounts_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].companyId')
    DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].clientId')

    SELECT ISNULL(
        (SELECT bankAccountId, companyId, clientId,
                RIGHT(clabe, 4) AS clabeLast4, bankCode, bankName, holderName,
                isVerified, verificationMethod, isDefault, isActive,
                CONVERT(NVARCHAR, verifiedAt, 127) AS verifiedAt,
                CONVERT(NVARCHAR, created_At, 127) AS created_At
         FROM [dbo].[bankAccounts]
         WHERE companyId = @companyId
           AND (@clientId IS NULL OR clientId = @clientId)
           AND isActive = 1
         ORDER BY isDefault DESC, created_At DESC
         FOR JSON PATH, ROOT('bankAccounts')),
        '{"bankAccounts":[]}'
    ) AS [jsonResult]
END
GO

-- ============================================================
IF OBJECT_ID('dbo.sp_bankAccounts_one', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_bankAccounts_one;
GO
CREATE PROCEDURE [dbo].[sp_bankAccounts_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @bankAccountId INT = JSON_VALUE(@pjsonfile, '$.bankAccounts[0].bankAccountId')

    -- Internal read for the verify endpoint / orchestrator: includes the full
    -- CLABE and pending verificationCents — never expose this SP's raw output
    -- to a client-facing response (modules must mask).
    SELECT ISNULL(
        (SELECT TOP 1 bankAccountId, companyId, clientId, clabe, bankCode, bankName,
                holderName, isVerified, verificationMethod, verificationCents,
                isDefault, isActive,
                CONVERT(NVARCHAR, verifiedAt, 127) AS verifiedAt
         FROM [dbo].[bankAccounts]
         WHERE bankAccountId = @bankAccountId
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        '{}'
    ) AS [jsonResult]
END
GO
