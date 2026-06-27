CREATE OR ALTER PROC [dbo].[sp_users] (@pjsonfile VARCHAR(MAX))
-- action 1 → INSERT
-- action 2 → UPDATE
-- action 3 → DELETE
AS
SET NOCOUNT ON

DECLARE @email     VARCHAR(100)
       ,@cellphone VARCHAR(20)
       ,@user_id   INT
       ,@action    INT
       ,@Error     VARCHAR(500) = ''

DECLARE @Outputmessage VARCHAR(MAX) = '{
  "result": [{ "value": "", "msg": "", "error": "" }]
}'

SET @action = (SELECT JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.users'))

-- ── INSERT ────────────────────────────────────────────────────────────────
IF @action = 1
BEGIN
    BEGIN TRY
        BEGIN TRAN
            INSERT INTO [dbo].[users] ([name], email, cellphone, [password], created_at)
            SELECT
                JSON_VALUE(value, '$.name')      AS [name],
                NULLIF(JSON_VALUE(value, '$.email'), '')      AS email,
                NULLIF(JSON_VALUE(value, '$.cellphone'), '')  AS cellphone,
                JSON_VALUE(value, '$.password')  AS [password],
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.users')
        COMMIT TRAN

        SET @user_id = SCOPE_IDENTITY()
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@user_id AS VARCHAR(20)));
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg',   'Inserted Successfully');
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
            @cellphone = NULLIF(JSON_VALUE(value, '$.cellphone'), '')
        FROM OPENJSON(@pjsonfile, '$.users')

        BEGIN TRAN
            UPDATE [dbo].[users] SET
                email     = ISNULL(@email,     email),
                cellphone = ISNULL(@cellphone, cellphone),
                [name]    = ISNULL(NULLIF(JSON_VALUE((SELECT value FROM OPENJSON(@pjsonfile,'$.users')), '$.name'), ''), [name]),
                [password]= ISNULL(NULLIF(JSON_VALUE((SELECT value FROM OPENJSON(@pjsonfile,'$.users')), '$.password'), ''), [password])
            WHERE [userId] = @user_id
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
GO
