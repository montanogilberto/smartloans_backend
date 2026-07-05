-- sp_check_contact v3
-- Finds a client by phone or email, checks for a linked user account,
-- and returns loan completion steps.
-- Requires: migration_users_phone.sql (dbo.users.cellphone column)

CREATE OR ALTER PROC [dbo].[sp_check_contact]
    @contact NVARCHAR(100)
AS
SET NOCOUNT ON;

-- ── 1. Find the client record ─────────────────────────────────────────────
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

IF @clientId IS NULL
BEGIN
    SELECT '{"found":false}' AS result;
    RETURN;
END

-- ── 2. Check linked user account (by email OR phone) ─────────────────────
DECLARE
    @userId     INT,
    @userName   NVARCHAR(100),
    @hasAccount INT = 0;

SELECT TOP 1
    @userId   = u.userId,
    @userName = u.name
FROM dbo.users u
WHERE (LEN(ISNULL(@email,'')) > 0     AND u.email     = @email)
   OR (LEN(ISNULL(@cellphone,'')) > 0 AND u.cellphone = @cellphone);

IF @userId IS NOT NULL SET @hasAccount = 1;

-- ── 3. Loan completion steps from ClientFaceRecognitions ──────────────────
-- Note: ClientFaceRecognitions is keyed by companyId only (no clientId FK yet).
-- We take the most recent record for this company as a best-effort.
DECLARE
    @isVerified       INT = 0,
    @contractAccepted INT = 0,
    @pagareAccepted   INT = 0;

SELECT TOP 1
    @isVerified       = CAST(ISNULL(cfr.is_verified,       0) AS INT),
    @contractAccepted = CAST(ISNULL(cfr.contract_accepted, 0) AS INT),
    @pagareAccepted   = 0   -- pagare_accepted column may not exist yet
FROM dbo.ClientFaceRecognitions cfr
WHERE cfr.companyId = @companyId
ORDER BY cfr.created_At DESC;

DECLARE @stepsCompleted INT =
    1   -- Info (client exists)
  + (CASE WHEN @qrBlobUrl IS NOT NULL AND LEN(@qrBlobUrl) > 0 THEN 1 ELSE 0 END)
  + 0   -- Stripe: checked on frontend
  + @isVerified
  + @contractAccepted
  + @pagareAccepted;

DECLARE @completionPct INT = (@stepsCompleted * 100) / 6;

-- ── 4. Build JSON response ────────────────────────────────────────────────
-- INCLUDE_NULL_VALUES ensures all fields are present even when NULL
SELECT (
    SELECT
        1               AS found,
        @clientId       AS clientId,
        @firstName      AS firstName,
        @lastName       AS lastName,
        @cellphone      AS cellphone,
        @email          AS email,
        @companyId      AS companyId,
        @userId         AS userId,
        @userName       AS userName,
        @hasAccount     AS hasAccount,
        @completionPct  AS completionPct,
        @stepsCompleted AS stepsCompleted,
        1               AS stepGeneralInfo,
        CASE WHEN @qrBlobUrl IS NOT NULL AND LEN(@qrBlobUrl) > 0 THEN 1 ELSE 0 END AS stepQr,
        @isVerified       AS stepBiometric,
        @contractAccepted AS stepContract,
        @pagareAccepted   AS stepPagare
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
) AS result;
GO
