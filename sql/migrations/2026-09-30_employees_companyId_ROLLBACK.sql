-- ROLLBACK for 2026-09-30_employees_companyId.sql
-- Restores the unscoped employees module exactly as it was before:
--   - SP bodies: sp_employees / sp_employees_one from
--     sql/migration/02_programmability.sql, sp_employees_all from
--     2026-09-30_fix_statuses_table_rename.sql (dbo.status join).
--   - Drops UQ_employees_companyId_email, FK_employees_companyId, companyId,
--     updated_at; re-adds the global UNIQUE(email).
-- WARNING: re-adding UNIQUE(email) fails if two companies registered the same
-- email after the forward migration — dedupe first. companyId values are lost.
-- Deploy the previous backend (GET /all_employees) together with this.

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_employees] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

	/*
	DECLARE @pjsonfile VARCHAR(MAX) = '{
    "employees": [
        {
            "employeeId": 1,
            "firstName": "John",
            "lastName": "Doe",
            "email": "john.doe@example.com",
            "phoneNumber": "123-456-7890",
            "address": "123 Main St, City, Country",
            "employmentTypeId": 1,
            "position": "Engineer",
            "departmentId": 2,
            "statusId": 1,
            "hireDate": "2021-01-15",
            "endDate": null,
            "emergencyContactName": "Jane Doe",
            "emergencyContactRelationship": "Spouse",
            "emergencyContactPhone": "123-456-7891",
            "notes": "Notes about John Doe",
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
    SET @action = (SELECT TOP 1 JSON_VALUE(value, '$.action') FROM OPENJSON(@pjsonfile, '$.employees'));

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1
        BEGIN
            -- Insert operation for the employees
            INSERT INTO [dbo].[employees] 
                ([firstName], [lastName], [email], [phoneNumber], [address], [employmentTypeId], 
                 [position], [departmentId], [statusId], [hireDate], [endDate], 
                 [emergencyContactName], [emergencyContactRelationship], [emergencyContactPhone], [notes], [createdAt])
            SELECT
                JSON_VALUE(value, '$.firstName'),
                JSON_VALUE(value, '$.lastName'),
                JSON_VALUE(value, '$.email'),
                JSON_VALUE(value, '$.phoneNumber'),
                JSON_VALUE(value, '$.address'),
                JSON_VALUE(value, '$.employmentTypeId'),
                JSON_VALUE(value, '$.position'),
                JSON_VALUE(value, '$.departmentId'),
                JSON_VALUE(value, '$.statusId'),
                JSON_VALUE(value, '$.hireDate'),
                JSON_VALUE(value, '$.endDate'),
                JSON_VALUE(value, '$.emergencyContactName'),
                JSON_VALUE(value, '$.emergencyContactRelationship'),
                JSON_VALUE(value, '$.emergencyContactPhone'),
                JSON_VALUE(value, '$.notes'),
                GETDATE()
            FROM OPENJSON(@pjsonfile, '$.employees');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2
        BEGIN
            -- Update operation for the employees
            UPDATE e
            SET 
                e.[firstName] = JSON_VALUE(j.value, '$.firstName'),
                e.[lastName] = JSON_VALUE(j.value, '$.lastName'),
                e.[email] = JSON_VALUE(j.value, '$.email'),
                e.[phoneNumber] = JSON_VALUE(j.value, '$.phoneNumber'),
                e.[address] = JSON_VALUE(j.value, '$.address'),
                e.[employmentTypeId] = JSON_VALUE(j.value, '$.employmentTypeId'),
                e.[position] = JSON_VALUE(j.value, '$.position'),
                e.[departmentId] = JSON_VALUE(j.value, '$.departmentId'),
                e.[statusId] = JSON_VALUE(j.value, '$.statusId'),
                e.[hireDate] = JSON_VALUE(j.value, '$.hireDate'),
                e.[endDate] = JSON_VALUE(j.value, '$.endDate'),
                e.[emergencyContactName] = JSON_VALUE(j.value, '$.emergencyContactName'),
                e.[emergencyContactRelationship] = JSON_VALUE(j.value, '$.emergencyContactRelationship'),
                e.[emergencyContactPhone] = JSON_VALUE(j.value, '$.emergencyContactPhone'),
                e.[notes] = JSON_VALUE(j.value, '$.notes')
            FROM 
                [dbo].[employees] e
            INNER JOIN 
                OPENJSON(@pjsonfile, '$.employees') j
                ON e.[employeeId] = JSON_VALUE(j.value, '$.employeeId');

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3
        BEGIN
            -- Delete operation for the employees
            DELETE FROM [dbo].[employees]
            WHERE [employeeId] IN (SELECT JSON_VALUE(value, '$.employeeId') FROM OPENJSON(@pjsonfile, '$.employees'));

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

CREATE OR ALTER PROC [dbo].[sp_employees_one] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON

BEGIN

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
    "employees": [
        {
        "employeeId": "1"
        }
     ]   
    }'
    */

    DECLARE @employeeId INT;

    SET @employeeId = CAST((SELECT JSON_VALUE(value, '$.employeeId') FROM OPENJSON(@pjsonfile, '$.employees')) AS INT);

    SELECT 
        [employeeId]
        ,[firstName]
        ,[lastName]
        ,[email]
        ,ISNULL([phoneNumber], '') AS phoneNumber
        ,ISNULL([address], '') AS address
        ,[employmentTypeId]
        ,ISNULL([position], '') AS position
        ,[departmentId]
        ,[statusId]
        ,ISNULL([hireDate], '') AS hireDate
        ,ISNULL([endDate], '') AS endDate
        ,ISNULL([emergencyContactName], '') AS emergencyContactName
        ,ISNULL([emergencyContactRelationship], '') AS emergencyContactRelationship
        ,ISNULL([emergencyContactPhone], '') AS emergencyContactPhone
        ,ISNULL([notes], '') AS notes
        ,[createdAt]
    FROM 
        [montanogilberto_smartloans].[dbo].[employees]
    WHERE
        employeeId = @employeeId
    FOR JSON AUTO, ROOT('employees');

END
GO



IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_employees_companyId_email')
    ALTER TABLE [dbo].[employees] DROP CONSTRAINT UQ_employees_companyId_email;
GO
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_employees_companyId')
    ALTER TABLE [dbo].[employees] DROP CONSTRAINT FK_employees_companyId;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.employees') AND name = 'companyId')
    ALTER TABLE [dbo].[employees] DROP COLUMN companyId;
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.employees') AND name = 'updated_at')
    ALTER TABLE [dbo].[employees] DROP COLUMN updated_at;
GO
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_employees_email')
    ALTER TABLE [dbo].[employees] ADD CONSTRAINT UQ_employees_email UNIQUE (email);
GO
