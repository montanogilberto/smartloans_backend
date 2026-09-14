-- clientLoginCodes: persisted SMS one-time-code login for POS customers
-- (dbo.clients rows with no dbo.users login at all). Mirrors the existing
-- in-memory OTP pair in modules/users.py (send_verification_code/verify_code)
-- but persisted, phone-scoped, and paired with client identity lookup +
-- attempt limiting, since that in-memory store was never designed for
-- "log a brand-new identity into a session," only "re-verify an existing one."
--
-- Code generation and the actual users/userCompanies auto-provisioning logic
-- stay in Python (modules/client_login.py) -- this proc is intentionally
-- thin CRUD, matching the sp_chartOfAccounts/sp_journalEntries split of
-- "business logic in Python, storage in a plain proc" used elsewhere.

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'clientLoginCodes')
CREATE TABLE [dbo].[clientLoginCodes] (
    clientLoginCodeId  INT IDENTITY(1,1) NOT NULL,
    phone               NVARCHAR(20)  NOT NULL,   -- E.164, matches dbo.clients.cellphone
    code                VARCHAR(6)    NOT NULL,
    expiresAt           DATETIME2(7)  NOT NULL,
    attempts            INT           NOT NULL DEFAULT (0),
    consumedAt          DATETIME2(7)  NULL,
    created_At          DATETIME2(7)  NOT NULL DEFAULT (GETUTCDATE()),
    CONSTRAINT PK_clientLoginCodes PRIMARY KEY CLUSTERED (clientLoginCodeId)
);
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_clientLoginCodes_phone' AND object_id = OBJECT_ID('dbo.clientLoginCodes'))
CREATE NONCLUSTERED INDEX IX_clientLoginCodes_phone ON dbo.clientLoginCodes (phone, consumedAt);
GO

-- action 1 -- insert a freshly generated code (Python generates code + expiresAt).
-- action 2 -- verify: body { phone, code }. Looks up the latest non-consumed,
--             non-expired row for phone; compares code; increments attempts on
--             mismatch (max 5, then that row can no longer succeed); marks
--             consumedAt on match. Also resolves + returns the linked client
--             (and, if any, linked user) so Python doesn't need a second round
--             trip to know what to auto-provision.
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

            IF @attempts >= 5
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
            DECLARE @clientJson NVARCHAR(MAX) = (
                SELECT TOP 1
                    c.clientId, c.companyId, c.first_name, c.last_name,
                    u.userId AS existingUserId
                FROM dbo.clients c
                LEFT JOIN dbo.users u ON u.clientId = c.clientId
                WHERE c.cellphone = @phone
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
    END TRY
    BEGIN CATCH
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
    END CATCH

Finish:
    SELECT @Outputmessage AS jsonResult;
END
GO
