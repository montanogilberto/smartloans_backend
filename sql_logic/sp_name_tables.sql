CREATE PROC [dbo].[sp_name_tables](@table_name VARCHAR(50))

AS

SET NOCOUNT ON

BEGIN



       --DECLARE @table_name VARCHAR(50) = 'users'

       DECLARE @sql NVARCHAR(MAX)



       -- Construct the dynamic SQL statement

       SET @sql = N'

              SELECT * FROM [dbo].' + QUOTENAME(@table_name) + '

              FOR JSON PATH, ROOT(''' + @table_name + ''')'



       -- Execute the dynamic SQL statement

       EXEC sp_executesql @sql

END