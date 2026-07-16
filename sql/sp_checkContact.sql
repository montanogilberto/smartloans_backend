SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- sp_checkContact v3 — @pjsonfile convention
-- Finds a client by phone (cellphone) or email, then checks if they already
-- have a user account linked via email OR phone.
-- Also returns loan completion steps (from ClientFaceRecognitions) so
-- CreateAccount.tsx can show a known client their onboarding progress
-- while they claim their login account.
--
-- Body: { "checkContact": [{ "contact": "phone-or-email" }] }
-- Requires dbo.users.cellphone (already present in production).

IF OBJECT_ID('dbo.sp_checkContact', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_checkContact;
GO

CREATE PROC [dbo].[sp_checkContact]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @contact NVARCHAR(100) = JSON_VALUE(@pjsonfile, '$.checkContact[0].contact')

    -- ── 1. Find the client record ───────────────────────────────────────
    DECLARE
        @clientId   INT,
        @firstName  NVARCHAR(100),
        @lastName   NVARCHAR(100),
        @cellphone  NVARCHAR(20),
        @email      NVARCHAR(100),
        @companyId  INT,
        @qrBlobUrl  NVARCHAR(500);

    SELECT TOP 1
        @clientId  = c.clientId,
        @firstName = c.first_name,
        @lastName  = c.last_name,
        @cellphone = c.cellphone,
        @email     = c.email,
        @companyId = c.companyId,
        @qrBlobUrl = c.qrBlobUrl
    FROM dbo.clients c
    WHERE c.cellphone = @contact
       OR c.email     = @contact;

    -- No client found → return found: false
    IF @clientId IS NULL
    BEGIN
        SELECT '{"found":false}' AS [jsonResult];
        RETURN;
    END

    -- ── 2. Check if a user account is linked (by email OR phone) ────────
    DECLARE
        @userId    INT,
        @userName  NVARCHAR(100),
        @hasAccount BIT = 0;

    SELECT TOP 1
        @userId   = u.userId,
        @userName = u.name
    FROM dbo.users u
    WHERE (u.email    = @email    AND @email    IS NOT NULL AND @email    <> '')
       OR (u.cellphone = @cellphone AND @cellphone IS NOT NULL AND @cellphone <> '');

    IF @userId IS NOT NULL
        SET @hasAccount = 1;

    -- ── 3. Loan completion steps ─────────────────────────────────────────
    -- Step 1: general info (client exists)         → always 1
    -- Step 2: QR saved to blob                     → qrBlobUrl not null
    -- Step 3: payment account (Stripe)             → checked on frontend
    -- Step 4: biometric verified                   → ClientFaceRecognitions.is_verified
    -- Step 5: contract accepted                    → ClientFaceRecognitions.contract_accepted
    -- Step 6: pagaré accepted                      → ClientFaceRecognitions.pagare_accepted

    DECLARE
        @isVerified       BIT = 0,
        @contractAccepted BIT = 0,
        @pagareAccepted   BIT = 0;

    SELECT TOP 1
        @isVerified       = ISNULL(cfr.is_verified, 0),
        @contractAccepted = ISNULL(cfr.contract_accepted, 0),
        @pagareAccepted   = ISNULL(cfr.pagare_accepted, 0)
    FROM dbo.ClientFaceRecognitions cfr
    WHERE cfr.companyId = @companyId
      AND cfr.clientId  = @clientId
    ORDER BY cfr.created_At DESC;

    DECLARE @stepsCompleted INT =
        1                                              -- general info
      + (CASE WHEN @qrBlobUrl  IS NOT NULL THEN 1 ELSE 0 END)
      + 0                                              -- Stripe: checked frontend
      + (CASE WHEN @isVerified       = 1 THEN 1 ELSE 0 END)
      + (CASE WHEN @contractAccepted = 1 THEN 1 ELSE 0 END)
      + (CASE WHEN @pagareAccepted   = 1 THEN 1 ELSE 0 END);

    DECLARE @completionPct INT = (@stepsCompleted * 100) / 6;

    -- ── 4. Return JSON ───────────────────────────────────────────────────
    SELECT (
        SELECT
            1                  AS found,
            @clientId          AS clientId,
            @firstName         AS firstName,
            @lastName          AS lastName,
            @cellphone         AS cellphone,
            @email             AS email,
            @companyId         AS companyId,
            @userId            AS userId,
            @userName          AS userName,
            CAST(@hasAccount AS INT) AS hasAccount,   -- 1 or 0, never NULL
            @completionPct     AS completionPct,
            @stepsCompleted    AS stepsCompleted,
            -- Individual step flags for detailed display
            1                  AS stepGeneralInfo,
            CAST(CASE WHEN @qrBlobUrl IS NOT NULL THEN 1 ELSE 0 END AS INT) AS stepQr,
            CAST(@isVerified       AS INT) AS stepBiometric,
            CAST(@contractAccepted AS INT) AS stepContract,
            CAST(@pagareAccepted   AS INT) AS stepPagare
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    ) AS [jsonResult];

    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO
