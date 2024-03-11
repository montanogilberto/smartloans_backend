SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROC [dbo].[sp_database_info_tables]

AS

SET NOCOUNT ON

BEGIN



       SELECT

              t.[name] AS table_name,

              (

                      SELECT

                             c.[name] AS column_name,

                             CASE

                                    WHEN typ.name = 'varchar' THEN typ.name + '(' + CAST(c.max_length AS VARCHAR(10)) + ')'

                                    ELSE typ.name

                             END AS data_type,

                             CASE

                                    WHEN (

                                           SELECT COUNT(*)

                                           FROM sys.indexes i

                                           INNER JOIN sys.index_columns ic ON i.[object_id] = ic.[object_id] AND i.index_id = ic.index_id

                                           WHERE i.is_primary_key = 1 AND ic.column_id = c.column_id

                                    ) > 0 THEN 'Yes'

                                    ELSE 'Not'

                             END AS is_primary_key,

                             CASE

                                    WHEN (

                                           SELECT COUNT(*)

                                           FROM sys.foreign_key_columns fk

                                           WHERE fk.parent_object_id = c.[object_id] AND fk.parent_column_id = c.column_id

                                    ) > 0 THEN 'Yes'

                                    ELSE 'Not'

                             END AS is_foreign_key

                      FROM

                             sys.columns c

                             INNER JOIN sys.types typ ON c.user_type_id = typ.user_type_id

                      WHERE

                             c.[object_id] = t.[object_id]

                      ORDER BY

                             c.column_id

                      FOR JSON PATH

              ) AS columns_info

       FROM

              sys.tables t

       ORDER BY

              t.[name]

FOR JSON PATH, ROOT('database_info');



END
GO
