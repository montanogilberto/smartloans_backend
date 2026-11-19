-- 2026-11-18 — RFC-013: 4-digit client login code (POSVending docs/rfcs/RFC-013-client-login-4-digit-code.md)
--
-- Changes to sp_clientLoginCodes (everything else is unchanged from
-- migration_history/migrations/2026-09-12_add_client_login_codes.sql):
--   action 1: refuses a new code when the phone already got 10 in the last 24 h
--             (error=1, value='DAILY_LIMIT'; modules/client_login.py answers 429).
--   action 2: a code locks after 3 wrong tries instead of 5.
-- Plus an index for the daily count.
--
-- NOT APPLIED. Before running it:
--   1. Check the [appEnv] startup banner / connection: local .env can point at production.
--   2. The live SP must match the 2026-09-12 script (known schema drift). Compare first:
--        SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.sp_clientLoginCodes'));
--      If it differs, merge these two changes into the live text instead of running this file.
--   3. Deploy order: this script BEFORE the backend that sends 4-digit codes.
--
-- No table or column changes: code VARCHAR(6) already holds 4 digits; created_At and attempts exist.

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_clientLoginCodes_phone_created' AND object_id = OBJECT_ID('dbo.clientLoginCodes'))
    CREATE NONCLUSTERED INDEX IX_clientLoginCodes_phone_created ON dbo.clientLoginCodes (phone, created_At);
GO

CREATE OR ALTER PROC [dbo].[sp_clientLoginCodes] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @Outputmessage NVARCHAR(MAX) = '{
      "result": [
        { "value": "", "msg": "", "error": "" }
      ]
    }'

    DECLARE @action INT = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.clientLoginCodes')
    );
    DECLARE @phone   NVARCHAR(20) = (
        SELECT TOP 1 JSON_VALUE(value, '$.phone') FROM OPENJSON(@pjsonfile, '$.clientLoginCodes')
    );

    BEGIN TRY
        IF @action = 1
        BEGIN
            DECLARE @code      VARCHAR(6)   = (SELECT TOP 1 JSON_VALUE(value, '$.code')      FROM OPENJSON(@pjsonfile, '$.clientLoginCodes'));
            DECLARE @expiresAt DATETIME2(7) = (SELECT TOP 1 TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.expiresAt')) FROM OPENJSON(@pjsonfile, '$.clientLoginCodes'));

            -- RFC-013: at most 10 codes per phone in 24 h, counted here so the cap
            -- survives restarts and holds across App Service instances.
            IF (SELECT COUNT(*) FROM dbo.clientLoginCodes
                WHERE phone = @phone AND created_At >= DATEADD(HOUR, -24, GETUTCDATE())) >= 10
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', 'DAILY_LIMIT');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Alcanzaste el límite de códigos por hoy. Intenta mañana o pide ayuda en sucursal.');
                GOTO Finish;
            END

            INSERT INTO dbo.clientLoginCodes (phone, code, expiresAt)
            VALUES (@phone, @code, @expiresAt);

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(SCOPE_IDENTITY() AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Code stored');
            GOTO Finish;
        END

        IF @action = 2
        BEGIN
            DECLARE @inputCode VARCHAR(6) = (SELECT TOP 1 JSON_VALUE(value, '$.code') FROM OPENJSON(@pjsonfile, '$.clientLoginCodes'));

            DECLARE @codeId INT, @storedCode VARCHAR(6), @expires DATETIME2(7), @attempts INT;
            SELECT TOP 1 @codeId = clientLoginCodeId, @storedCode = code, @expires = expiresAt, @attempts = attempts
            FROM dbo.clientLoginCodes
            WHERE phone = @phone AND consumedAt IS NULL
            ORDER BY clientLoginCodeId DESC;

            IF @codeId IS NULL
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No hay código para este número.');
                GOTO Finish;
            END

            -- RFC-013: 3 tries per code (4-digit codes).
            IF @attempts >= 3
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Demasiados intentos. Solicita un código nuevo.');
                GOTO Finish;
            END

            IF GETUTCDATE() > @expires
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'El código expiró.');
                GOTO Finish;
            END

            IF @storedCode <> @inputCode
            BEGIN
                UPDATE dbo.clientLoginCodes SET attempts = attempts + 1 WHERE clientLoginCodeId = @codeId;
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Código incorrecto.');
                GOTO Finish;
            END

            UPDATE dbo.clientLoginCodes SET consumedAt = GETUTCDATE() WHERE clientLoginCodeId = @codeId;

            -- Resolve the client + any already-linked user in the same call,
            -- so Python knows in one round trip whether to auto-provision.
            -- firstLoginCompleted rides along too so verify_client_login_code
            -- doesn't need a second round trip to decide password-step vs skip.
            -- Compare by last-10-digits, NOT exact string: dbo.clients.cellphone
            -- is stored however it was originally typed (often plain 10-digit,
            -- no +52), while @phone here is always E.164-normalized (Python's
            -- _normalize_phone) -- an exact match silently fails for most real
            -- clients. Same normalization ClientSelector.tsx already uses
            -- client-side (normalizePhoneDigits + endsWith).
            DECLARE @clientJson NVARCHAR(MAX) = (
                SELECT TOP 1
                    c.clientId, c.companyId, c.first_name, c.last_name,
                    u.userId AS existingUserId,
                    ISNULL(u.firstLoginCompleted, 0) AS firstLoginCompleted,
                    -- 2026-09-28: the user's CURRENT role in this company, so
                    -- client_login.py never overwrites it with 'pos'.
                    -- hasCompanyRole is never NULL (FOR JSON PATH drops NULLs).
                    CASE WHEN uc.userId IS NOT NULL THEN 1 ELSE 0 END AS hasCompanyRole,
                    uc.roleName AS existingRoleCode,
                    r.name AS existingRoleName
                FROM dbo.clients c
                LEFT JOIN dbo.users u ON u.clientId = c.clientId
                LEFT JOIN dbo.userCompanies uc ON uc.userId = u.userId AND uc.companyId = c.companyId
                LEFT JOIN dbo.roles r ON r.code = uc.roleName
                WHERE RIGHT(REPLACE(c.cellphone, '+', ''), 10) = RIGHT(REPLACE(@phone, '+', ''), 10)
                ORDER BY CASE WHEN u.userId IS NOT NULL THEN 0 ELSE 1 END
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            IF @clientJson IS NULL
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No encontramos un cliente con ese teléfono.');
                GOTO Finish;
            END

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Verified');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@codeId AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].client', JSON_QUERY(@clientJson));
        END

        -- action 3 -- status: body { phone }. No code/password involved --
        -- just "does this phone have an account, and has that account
        -- finished first-login password onboarding". Lets Python decide
        -- whether to send an OTP SMS at all (send_client_login_code) without
        -- ever touching dbo.clients/dbo.users directly.
        IF @action = 3
        BEGIN
            -- companyName rides along so Python can brand the OTP SMS as this
            -- client's own company (e.g. "Lavanderia") instead of the
            -- _send_sms_otp default of "SmartLoans" -- see modules/users.py.
            DECLARE @statusJson NVARCHAR(MAX) = (
                SELECT TOP 1
                    c.clientId, c.companyId, c.first_name, c.last_name,
                    co.name AS companyName,
                    u.userId AS existingUserId,
                    ISNULL(u.firstLoginCompleted, 0) AS firstLoginCompleted
                FROM dbo.clients c
                LEFT JOIN dbo.users u ON u.clientId = c.clientId
                LEFT JOIN dbo.companies co ON co.companyId = c.companyId
                WHERE RIGHT(REPLACE(c.cellphone, '+', ''), 10) = RIGHT(REPLACE(@phone, '+', ''), 10)
                ORDER BY CASE WHEN u.userId IS NOT NULL THEN 0 ELSE 1 END
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            IF @statusJson IS NULL
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No encontramos una cuenta con ese número.');
                GOTO Finish;
            END

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Status');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].client', JSON_QUERY(@statusJson));
        END

        -- action 4 -- password login: body { phone, password }. Returning
        -- client only (firstLoginCompleted=1 from action 3/2) -- no OTP.
        -- Password compared in SQL so Python never sees/handles the stored
        -- value directly. Plaintext compare matches sp_login's existing
        -- staff password scheme (dbo.users.password varchar(50), no
        -- hashing anywhere in this backend today).
        IF @action = 4
        BEGIN
            DECLARE @inputPassword VARCHAR(50) = (
                SELECT TOP 1 JSON_VALUE(value, '$.password') FROM OPENJSON(@pjsonfile, '$.clientLoginCodes')
            );

            DECLARE @pwClientJson NVARCHAR(MAX) = (
                SELECT TOP 1
                    c.clientId, c.companyId, c.first_name, c.last_name, u.userId,
                    uc.roleName AS existingRoleCode,
                    r.name AS existingRoleName
                FROM dbo.clients c
                INNER JOIN dbo.users u ON u.clientId = c.clientId
                LEFT JOIN dbo.userCompanies uc ON uc.userId = u.userId AND uc.companyId = c.companyId
                LEFT JOIN dbo.roles r ON r.code = uc.roleName
                WHERE RIGHT(REPLACE(c.cellphone, '+', ''), 10) = RIGHT(REPLACE(@phone, '+', ''), 10)
                  AND u.password IS NOT NULL AND u.password <> ''
                  AND u.password = @inputPassword
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            IF @pwClientJson IS NULL
            BEGIN
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Teléfono o contraseña incorrectos.');
                GOTO Finish;
            END

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Verified');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].client', JSON_QUERY(@pwClientJson));
        END
    END TRY
    BEGIN CATCH
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
    END CATCH

Finish:
    SELECT @Outputmessage AS jsonResult;
END
GO
