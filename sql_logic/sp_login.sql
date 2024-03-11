CREATE PROC [dbo].[sp_login] (@pjsonfile VARCHAR(MAX))
AS

/*
DECLARE @pjsonfile VARCHAR(MAX) = '{
"logins": [
    {
    "username": "admin",
    "password": "567"
    }
]
}'
*/

SET NOCOUNT ON

BEGIN
    DECLARE @Outputmessage VARCHAR(MAX) = '
    {
    "result": [
            {
                "value": "",
                "msg": "",
                "error": ""
            }
        ]
    }',
    @userId VARCHAR(50) = '';


    WITH CTE_login AS
    (
        SELECT
            JSON_VALUE(value, '$.username') AS [username],
            JSON_VALUE(value, '$.password') AS [password]
        FROM OPENJSON(@pjsonfile, '$.logins')
    )

    SELECT
        @userId = userId
    FROM
        dbo.users u
        INNER JOIN CTE_login l  ON u.name = l.username AND u.[password] = l.[password];

    --select @userId

    IF @userId IS NOT NULL AND LEN(@userId) > 0
    BEGIN
        print('entro')
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', cast(@userid as VARCHAR(50)));
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'User Valid');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '');

    END
    ELSE
    BEGIN
        print('No entro')
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', cast(@userid as VARCHAR(50)));
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'User Invalid');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '-1');

    END

    SELECT @Outputmessage as Outputmessage

END