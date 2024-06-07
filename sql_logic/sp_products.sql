CREATE PROC [dbo].[sp_products] (@pjsonfile VARCHAR(MAX))
--INSERT --> 1
--UPDATE --> 2
--DELETE --> 3
AS
SET NOCOUNT ON;

/*
DECLARE @pjsonfile VARCHAR(MAX) = '{
    "products": [
        {
            "productId": 1,
            "name": "exaliv",
            "barCode": "",
            "code": "",
            "dateOfExpire": "2024-03-12",
            "productFormId": 1,
            "manufactureId": 1,
            "description": "",
            "createdAt": "2024-03-12T20:31:06.490",
            "updatedAt": "1900-01-01T00:00:00"
        }
    ]
}'
*/

DECLARE @Outputmessage NVARCHAR(MAX) = '
{
  "result": [
  {
     "value": "",
     "msg": "",
     "error": ""
   }
  ]
}',
@Error NVARCHAR(500) = '',
@action INT,
@product_id INT;

BEGIN
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.products'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert
            INSERT INTO [dbo].[products] ([name], [barCode], [code], [dateOfExpire], [productFormId], [manufactureId], [description], [createdAt], [updatedAt])
            SELECT
                JSON_VALUE(value, '$.name'),
                JSON_VALUE(value, '$.barCode'),
                JSON_VALUE(value, '$.code'),
                JSON_VALUE(value, '$.dateOfExpire'),
                JSON_VALUE(value, '$.productFormId'),
                JSON_VALUE(value, '$.manufactureId'),
                JSON_VALUE(value, '$.description'),
                GETDATE(),
                NULL
            FROM OPENJSON(@pjsonfile, '$.products');

            SET @product_id = SCOPE_IDENTITY();
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@product_id AS NVARCHAR(50)));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update
            UPDATE p
            SET
                p.[name] = JSON_VALUE(j.value, '$.name'),
                p.[barCode] = JSON_VALUE(j.value, '$.barCode'),
                p.[code] = JSON_VALUE(j.value, '$.code'),
                p.[dateOfExpire] = JSON_VALUE(j.value, '$.dateOfExpire'),
                p.[productFormId] = JSON_VALUE(j.value, '$.productFormId'),
                p.[manufactureId] = JSON_VALUE(j.value, '$.manufactureId'),
                p.[description] = JSON_VALUE(j.value, '$.description'),
                p.[createdAt] = COALESCE(JSON_VALUE(j.value, '$.createdAt'), GETDATE()),
                p.[updatedAt] = JSON_VALUE(j.value, '$.updatedAt')
            FROM
                [dbo].[products] p
            INNER JOIN
                OPENJSON(@pjsonfile, '$.products') j
                ON p.[productId] = JSON_VALUE(j.value, '$.productId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete
            DELETE p
            FROM
                [dbo].[products] p
            INNER JOIN
                OPENJSON(@pjsonfile, '$.products') j
                ON p.[productId] = JSON_VALUE(j.value, '$.productId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;

        SET @Error = ERROR_MESSAGE();
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', @Error);
    END CATCH

    -- Return the result
    SELECT
        JSON_VALUE(value, '$.value') AS [value],
        JSON_VALUE(value, '$.msg') AS [msg],
        JSON_VALUE(value, '$.error') AS [error]
    FROM OPENJSON(@Outputmessage, '$.result');
END
GO
