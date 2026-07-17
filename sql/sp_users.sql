CREATE OR ALTER PROC [dbo].[sp_users] (@pjsonfile VARCHAR(MAX))
-- action 1 → INSERT
-- action 2 → UPDATE (also upserts dbo.userCompanies when companyId is provided)
-- action 3 → DELETE
AS
SET NOCOUNT ON

DECLARE @email      VARCHAR(100)
       ,@cellphone  VARCHAR(20)
       ,@user_id    INT
       ,@action     INT
       ,@companyId  INT
       ,@branchId   INT
       ,@roleCode   VARCHAR(50)
       ,@roleId     INT
       ,@clientId   INT
       ,@Error      VARCHAR(500) = ''

DECLARE @Outputmessage VARCHAR(MAX) = '{
  "result": [{ "value": "", "msg": "", "error": "" }]
}'

SET @action = (SELECT JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.users'))

-- ── INSERT ────────────────────────────────────────────────────────────────
IF @action = 1
BEGIN
    BEGIN TRY
        DECLARE @newName  VARCHAR(100) =
            (SELECT JSON_VALUE(value, '$.name') FROM OPENJSON(@pjsonfile, '$.users'))
        DECLARE @newEmail VARCHAR(100) =
            NULLIF((SELECT JSON_VALUE(value, '$.email') FROM OPENJSON(@pjsonfile, '$.users')), '')

        -- Username must be unique — belt-and-suspenders alongside the
        -- dedicated /check_username lookup the frontend calls before submit.
        IF EXISTS (SELECT 1 FROM dbo.users WHERE [name] = @newName)
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   'El nombre de usuario ya existe.')
        END
        -- Email must be unique too — checkContact only catches this when a
        -- dbo.clients row also exists for that email (e.g. POS-only or
        -- email-only "loans" accounts have no client row, so it wouldn't
        -- have been caught upstream).
        ELSE IF @newEmail IS NOT NULL AND EXISTS (SELECT 1 FROM dbo.users WHERE email = @newEmail)
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   'El email ya está registrado.')
        END
        ELSE
        BEGIN
            BEGIN TRAN
                -- clientId links this login to an existing dbo.clients row
                -- (set when an already-known client — found via checkContact,
                -- no account yet — is claiming their account) so the two
                -- records aren't left disconnected.
                INSERT INTO [dbo].[users] ([name], email, cellphone, [password], created_at, clientId)
                SELECT
                    JSON_VALUE(value, '$.name')      AS [name],
                    NULLIF(JSON_VALUE(value, '$.email'), '')      AS email,
                    NULLIF(JSON_VALUE(value, '$.cellphone'), '')  AS cellphone,
                    JSON_VALUE(value, '$.password')  AS [password],
                    GETDATE(),
                    TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId'))  AS clientId
                FROM OPENJSON(@pjsonfile, '$.users')
            COMMIT TRAN

            SET @user_id = SCOPE_IDENTITY()
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@user_id AS VARCHAR(20)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   'Inserted Successfully');
        END
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK
        SET @Error = ERROR_MESSAGE()
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   @Error)
    END CATCH
END

-- ── UPDATE ────────────────────────────────────────────────────────────────
IF @action = 2
BEGIN
    BEGIN TRY
        SELECT
            @user_id   = JSON_VALUE(value, '$.user_id'),
            @email     = NULLIF(JSON_VALUE(value, '$.email'), ''),
            @cellphone = NULLIF(JSON_VALUE(value, '$.cellphone'), ''),
            @companyId = NULLIF(JSON_VALUE(value, '$.companyId'), ''),
            @branchId  = NULLIF(JSON_VALUE(value, '$.branchId'), ''),
            @roleCode  = NULLIF(JSON_VALUE(value, '$.roleCode'), ''),
            @clientId  = TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId'))
        FROM OPENJSON(@pjsonfile, '$.users')

        BEGIN TRAN
            -- clientId mirrors the INSERT path: link/re-link this login to a
            -- dbo.clients row after creation, not just at signup time.
            UPDATE [dbo].[users] SET
                email     = ISNULL(@email,     email),
                cellphone = ISNULL(@cellphone, cellphone),
                clientId  = ISNULL(@clientId,  clientId),
                [name]    = ISNULL(NULLIF(JSON_VALUE((SELECT value FROM OPENJSON(@pjsonfile,'$.users')), '$.name'), ''), [name]),
                [password]= ISNULL(NULLIF(JSON_VALUE((SELECT value FROM OPENJSON(@pjsonfile,'$.users')), '$.password'), ''), [password])
            WHERE [userId] = @user_id

            -- Company/branch/role selection (step "Acceso") → upsert userCompanies.
            -- sp_login reads role/company/branch from here, not from dbo.users.
            IF @companyId IS NOT NULL
            BEGIN
                SELECT @roleId = roleId FROM dbo.roles WHERE code = @roleCode AND active = 1

                IF EXISTS (SELECT 1 FROM dbo.userCompanies WHERE userId = @user_id AND companyId = @companyId)
                BEGIN
                    UPDATE dbo.userCompanies SET
                        branchId   = ISNULL(@branchId, branchId),
                        roleId     = ISNULL(@roleId, roleId),
                        roleName   = ISNULL(@roleCode, roleName),
                        updated_at = GETDATE()
                    WHERE userId = @user_id AND companyId = @companyId
                END
                ELSE
                BEGIN
                    INSERT INTO dbo.userCompanies
                        (userId, companyId, branchId, isDefault, roleName, active, created_at, roleId)
                    VALUES
                        (@user_id, @companyId, @branchId,
                         CASE WHEN EXISTS (SELECT 1 FROM dbo.userCompanies WHERE userId = @user_id) THEN 0 ELSE 1 END,
                         @roleCode, 1, GETDATE(), @roleId)
                END
            END
        COMMIT TRAN

        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@user_id AS VARCHAR(20)));
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   'Updated Successfully');
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK
        SET @Error = ERROR_MESSAGE()
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   @Error)
    END CATCH
END

SELECT
    JSON_VALUE(value, '$.value') AS [value],
    JSON_VALUE(value, '$.msg')   AS [msg],
    JSON_VALUE(value, '$.error') AS [error]
FROM OPENJSON(@Outputmessage, '$.result')
