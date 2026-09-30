-- =============================================================================
-- Fix: dbo.statuses was renamed to dbo.status in the live DB
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: GET /all_employees and GET /all_statuses return 500 in production:
--   "Invalid object name 'dbo.statuses'" (verified 2026-09-30). The live DB
-- has dbo.status (statusId, status, createdAt — same columns) and no
-- dbo.statuses; no migration in this repo did that rename, so these four
-- SPs were never updated. SQL Server resolves table names at run time
-- (deferred name resolution), so nothing failed until the SP was called.
--
-- SCOPE: the four SPs that referenced dbo.statuses, table name only.
--   - sp_employees_all   (INNER JOIN — every employee row needs a status)
--   - sp_statuses / sp_statuses_all / sp_statuses_one
--   Bodies are otherwise identical to sql/migration/02_programmability.sql;
--   sp_statuses_all/_one also drop the hardcoded 3-part
--   [montanogilberto_smartloans].[dbo] prefix.
--   JSON root keys stay 'statuses' — the frontend reads that key.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_employees_all]
AS
SET NOCOUNT ON

BEGIN
SELECT 
     e.[employeeId]
    ,e.[firstName]
    ,e.[lastName]
    ,e.[email]
    ,e.[phoneNumber]
    ,e.[address]
    ,et.[employmentType]
    ,e.[position]
    ,d.[departmentName]
    ,s.[status]
    ,e.[hireDate]
    ,e.[endDate]
    ,e.[emergencyContactName]
    ,e.[emergencyContactRelationship]
    ,e.[emergencyContactPhone]
    ,e.[notes]
    ,e.[createdAt]
  FROM 
    [dbo].[employees] e
    INNER JOIN [dbo].[employmentTypes] et ON et.[employmentTypeId] = e.[employmentTypeId]
    INNER JOIN [dbo].[departments] d ON d.[departmentId] = e.[departmentId]
    INNER JOIN [dbo].[status] s ON s.[statusId] = e.[statusId]
    FOR JSON AUTO, ROOT('employees');
END
GO

CREATE OR ALTER PROC [dbo].[sp_statuses] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "statuses": [
        {
            "statusId": 1,
            "status": "active",
            "createdAt": "2024-06-25T22:27:04.492Z",
            "action": "1"
        }
    ]
}
'
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
    @action INT;

    -- Determine action from the JSON
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.statuses'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the statuses
            INSERT INTO [dbo].[status] 
                ([status], [createdAt])
            SELECT
                JSON_VALUE(value, '$.status'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.statuses');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the statuses
            UPDATE s
            SET 
                s.[status] = JSON_VALUE(j.value, '$.status')
            FROM 
                [dbo].[status] s
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.statuses') j
                ON s.[statusId] = JSON_VALUE(j.value, '$.statusId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the statuses
            DELETE FROM [dbo].[status]
            WHERE [statusId] IN (SELECT JSON_VALUE(value, '$.statusId') FROM OPENJSON(@pjsonfile, '$.statuses'));

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

CREATE OR ALTER PROC [dbo].[sp_statuses_all]
AS
SET NOCOUNT ON

BEGIN
    SELECT
        [statusId],
        [status],
        [createdAt]
    FROM [dbo].[status]
    FOR JSON AUTO, ROOT('statuses');
END
GO

CREATE OR ALTER PROC [dbo].[sp_statuses_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "statuses": [
        {
        "statusId": "1"
        }
     ]   
    }'
    */

    DECLARE @statusId INT;

    SET @statusId = CAST((SELECT JSON_VALUE(value, '$.statusId') FROM OPENJSON(@pjsonfile, '$.statuses')) AS INT);

    SELECT 
        [statusId]
        ,[status]
        ,[createdAt]
    FROM 
        [dbo].[status]
    WHERE
        statusId = @statusId
    FOR JSON AUTO, ROOT('statuses');

END
GO
