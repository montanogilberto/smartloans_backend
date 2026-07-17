SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- sp_checkUsername
-- Given a batch of candidate usernames (the typed one + generated suggestions),
-- returns which ones are already taken in dbo.users.name. The caller (Python)
-- computes availability + which suggestions are free from this.
--
-- Body: { "checkUsername": [{ "usernames": ["gilberto", "gilberto1", "gilberto2"] }] }
-- Returns: { "taken": [{ "name": "gilberto" }] }

IF OBJECT_ID('dbo.sp_checkUsername', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_checkUsername;
GO

CREATE PROC [dbo].[sp_checkUsername]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @takenJson NVARCHAR(MAX) = (
        SELECT u.[name]
        FROM dbo.users u
        INNER JOIN OPENJSON(@pjsonfile, '$.checkUsername[0].usernames') c
            ON u.[name] = c.[value]
        FOR JSON PATH
    );

    SELECT '{"taken":' + ISNULL(@takenJson, '[]') + '}' AS [jsonResult];

    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult];
    END CATCH
END
GO
