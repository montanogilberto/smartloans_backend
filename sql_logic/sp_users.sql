CREATE PROC [dbo].[sp_users] (@pjsonfile VARCHAR(MAX))
--INSERT --> 1
--UPDATE --> 2
--DELETE --> 3
AS


/*
DECLARE @pjsonfile VARCHAR(MAX) = '{
  "users": [
    {
      "user_id": "0", --fix
      "email": "email2@example.com",
      "name": "test2", --userName
      "password": "123",
      "action": "1" --fix
    }
  ]
}'
*/

SET NOCOUNT ON
DECLARE @email varchar(50)
		,@user_id INT
        ,@action INT

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
    @Error VARCHAR(500) = ''

    SET @action = (SELECT JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.users'))

    --Insert
    IF @action = '1'
    BEGIN
       BEGIN TRY
          BEGIN TRAN
             INSERT INTO [dbo].[users] ([name],email,[password],created_at)
             SELECT
                JSON_VALUE(value, '$.name') AS [name],
				JSON_VALUE(value, '$.email') AS [email],
				JSON_VALUE(value, '$.password') AS [password],
				GETDATE() AS created_at
             FROM OPENJSON(@pjsonfile, '$.users')
          COMMIT TRAN

		  -- Get last Identity stored
		  SET @user_id = SCOPE_IDENTITY()

          SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', ''+cast(@user_id as VARCHAR(50))+'');
          SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');

       END TRY
       BEGIN CATCH
          ROLLBACK
          SET @ERROR = ERROR_MESSAGE()
          SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1')
          SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error)
       END CATCH
    END

    --Update

    IF @action = '2'
    BEGIN
       BEGIN TRY


          SELECT
             @email = JSON_VALUE(value, '$.email'),
             @user_id = JSON_VALUE(value, '$.user_id')
          FROM
             OPENJSON(@pjsonfile, '$.users')

          BEGIN TRAN

             UPDATE [dbo].[users] SET
                email = @email
             WHERE
                [userId] = @user_id

          COMMIT TRAN

          SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', @user_id);
          SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successufully');


       END TRY
       BEGIN CATCH
          SET @ERROR = @@ERROR
          SET @Outputmessage = JSON_MODIFY(@pjsonfile, '$.users[0].value', @user_id);
          SET @Outputmessage = JSON_MODIFY(@pjsonfile, '$.users[0].msg', @Error);
          SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
       END CATCH
    END
    /**/

    SELECT
       JSON_VALUE(value, '$.value') AS [value],
       JSON_VALUE(value, '$.msg') AS [msg],
	   JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result')

END
GO
