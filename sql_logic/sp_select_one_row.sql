CREATE PROC [dbo].[sp_select_one_row](@pjsonfile VARCHAR(MAX))

AS

SET NOCOUNT ON

 

/*

DECLARE @pjsonfile VARCHAR(MAX) = '{

  "utils": [

    {

      "table_name": "users",

      "valueId": "1",

    }

  ]

}'

*/

 

BEGIN

 

       DECLARE @Outputmessage VARCHAR(MAX) = '

              {

                "result": [

                      {

                        "value": "",

                        "msg": ""

                      }

                ]

              }'

 

       DECLARE

       @table_name VARCHAR(50),

       @valueId VARCHAR(50)

 

       --DECLARE @table_name VARCHAR(50) = 'users'

       DECLARE

              @sql NVARCHAR(MAX),

              @field VARCHAR(100)

 

       SELECT

              @table_name = JSON_VALUE(value, '$.table_name'),

              @valueId = JSON_VALUE(value, '$.valueId')

       FROM OPENJSON(@pjsonfile, '$.utils')

 

       SELECT

              @field = c.[name]

       FROM

              sys.tables t

              INNER JOIN sys.columns c ON c.object_id = t.object_id

       WHERE

              t.name = @table_name

              AND is_identity = 1

 

       IF @field IS NOT NULL

       BEGIN

              -- Construct the dynamic SQL statement

              SET @sql = N'

                      SELECT * FROM [dbo].' + QUOTENAME(@table_name) + '

                      WHERE ' + QUOTENAME(@field) + ' = @valueId

                      FOR JSON PATH, ROOT(''' + @table_name + ''')'

 

              -- Execute the dynamic SQL statement with parameters

              EXEC sp_executesql @sql, N'@valueId NVARCHAR(50)', @valueId = @valueId

       END

       ELSE

       BEGIN

              PRINT 'No identity column found'

              SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].result', '-1')

              SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'No identity column found')

 

              SELECT

                      JSON_VALUE(value, '$.value') AS [value],

                      JSON_VALUE(value, '$.msg') AS [msg]

              FROM OPENJSON(@Outputmessage, '$.result')

       END

 

END
