-- =============================================================================
-- Company-scope dbo.employees (PRD: posgmo-factory/tests/prd_employee.json)
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB, AFTER
-- 2026-09-30_fix_statuses_table_rename.sql (the SPs below join dbo.status).
--
-- WHY: dbo.employees has no companyId, so /all_employees returned every
-- company's staff and sp_employees let any company edit/delete any employee.
-- The payroll expense picker inherited the same leak (see KNOWN LIMITATION in
-- 2026-09-03_add_expense_payroll.sql).
--
-- SCOPE:
--   - employees.companyId INT NULL + FK_employees_companyId → companies.
--     Existing rows stay NULL (demo seed rows, no reliable company) and stop
--     appearing in any company's list until someone assigns them.
--   - employees.updated_at DATETIME NULL.
--   - Global UNIQUE(email) → UNIQUE(companyId, email). The old constraint has
--     an auto-generated name (UQ__employee__...), so it is looked up by
--     column instead of by name.
--   - sp_employees: every action scoped by companyId; returns the
--     sp_suppliers shape (one row, one column [jsonResult]
--     {status,message,value}); delete refused while payroll expenses or
--     project assignments reference the employee.
--   - sp_employees_all / sp_employees_one: take @pjsonfile with companyId,
--     FOR JSON PATH with ids + display names flat (the old _all used
--     FOR JSON AUTO, which nested names as et[].d[].s[] and dropped the ids).
-- Idempotent: guarded ALTERs + CREATE OR ALTER, safe to re-run.
-- Rollback: 2026-09-30_employees_companyId_ROLLBACK.sql
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.employees') AND name = 'companyId')
    ALTER TABLE [dbo].[employees] ADD companyId INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_employees_companyId')
    ALTER TABLE [dbo].[employees]
        ADD CONSTRAINT FK_employees_companyId FOREIGN KEY (companyId)
        REFERENCES [dbo].[companies] (companyId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('dbo.employees') AND name = 'updated_at')
    ALTER TABLE [dbo].[employees] ADD updated_at DATETIME NULL;
GO

-- Drop the single-column UNIQUE(email), whatever its generated name is.
DECLARE @uq SYSNAME, @sql NVARCHAR(400);
SELECT @uq = kc.name
FROM sys.key_constraints kc
JOIN sys.index_columns ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
JOIN sys.columns c        ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE kc.parent_object_id = OBJECT_ID('dbo.employees')
  AND kc.type = 'UQ'
GROUP BY kc.name
HAVING COUNT(*) = 1 AND MAX(c.name) = 'email';

IF @uq IS NOT NULL
BEGIN
    SET @sql = N'ALTER TABLE [dbo].[employees] DROP CONSTRAINT ' + QUOTENAME(@uq);
    EXEC sp_executesql @sql;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_employees_companyId_email')
    ALTER TABLE [dbo].[employees]
        ADD CONSTRAINT UQ_employees_companyId_email UNIQUE (companyId, email);
GO

-- =============================================================================
-- sp_employees — CRUD (action 1 INSERT / 2 UPDATE / 3 DELETE)
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_employees]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    /*
    DECLARE @pjsonfile VARCHAR(MAX) = '{
      "employees": [{
        "companyId": 1008, "employeeId": 0,
        "firstName": "Ana", "lastName": "López", "email": "ana@example.com",
        "phoneNumber": "6621234567", "address": "", "position": "Cajera",
        "employmentTypeId": 1, "departmentId": 3, "statusId": 1,
        "hireDate": "2026-09-01", "endDate": null,
        "emergencyContactName": "", "emergencyContactRelationship": "",
        "emergencyContactPhone": "", "notes": "",
        "action": 1
      }]
    }'
    */

    DECLARE @Outputmessage NVARCHAR(MAX);
    DECLARE @Action INT, @companyId INT, @employeeId INT, @email NVARCHAR(100);

    DECLARE @payload TABLE (
        action INT,
        employeeId INT,
        companyId INT,
        firstName NVARCHAR(50),
        lastName NVARCHAR(50),
        email NVARCHAR(100),
        phoneNumber NVARCHAR(20),
        address NVARCHAR(255),
        employmentTypeId INT,
        position NVARCHAR(100),
        departmentId INT,
        statusId INT,
        hireDate DATE,
        endDate DATE,
        emergencyContactName NVARCHAR(100),
        emergencyContactRelationship NVARCHAR(50),
        emergencyContactPhone NVARCHAR(20),
        notes NVARCHAR(MAX)
    );

    INSERT INTO @payload
    SELECT TOP 1
        TRY_CAST(JSON_VALUE(value, '$.action') AS INT),
        TRY_CAST(JSON_VALUE(value, '$.employeeId') AS INT),
        TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.firstName'))), ''),
        NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.lastName'))), ''),
        NULLIF(LOWER(LTRIM(RTRIM(JSON_VALUE(value, '$.email')))), ''),
        NULLIF(JSON_VALUE(value, '$.phoneNumber'), ''),
        NULLIF(JSON_VALUE(value, '$.address'), ''),
        TRY_CAST(JSON_VALUE(value, '$.employmentTypeId') AS INT),
        NULLIF(JSON_VALUE(value, '$.position'), ''),
        TRY_CAST(JSON_VALUE(value, '$.departmentId') AS INT),
        TRY_CAST(JSON_VALUE(value, '$.statusId') AS INT),
        TRY_CAST(NULLIF(JSON_VALUE(value, '$.hireDate'), '') AS DATE),
        TRY_CAST(NULLIF(JSON_VALUE(value, '$.endDate'), '') AS DATE),
        NULLIF(JSON_VALUE(value, '$.emergencyContactName'), ''),
        NULLIF(JSON_VALUE(value, '$.emergencyContactRelationship'), ''),
        NULLIF(JSON_VALUE(value, '$.emergencyContactPhone'), ''),
        NULLIF(JSON_VALUE(value, '$.notes'), '')
    FROM OPENJSON(@pjsonfile, '$.employees');

    SELECT @Action = action, @companyId = companyId, @employeeId = employeeId, @email = email
    FROM @payload;

    IF @companyId IS NULL
    BEGIN
        SET @Outputmessage = '{"status": "error", "message": "companyId is required."}';
        GOTO Finish;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Action IN (1, 2)
        BEGIN
            IF EXISTS (SELECT 1 FROM @payload
                       WHERE firstName IS NULL OR lastName IS NULL OR email IS NULL
                          OR employmentTypeId IS NULL OR departmentId IS NULL OR statusId IS NULL)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "firstName, lastName, email, employmentTypeId, departmentId and statusId are required."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            IF EXISTS (SELECT 1 FROM [dbo].[employees]
                       WHERE companyId = @companyId AND email = @email
                         AND employeeId <> ISNULL(CASE WHEN @Action = 2 THEN @employeeId END, 0))
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another employee with this email already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END
        END

        IF @Action IN (2, 3)
           AND NOT EXISTS (SELECT 1 FROM [dbo].[employees]
                           WHERE employeeId = @employeeId AND companyId = @companyId)
        BEGIN
            SET @Outputmessage = '{"status": "error", "message": "Employee not found."}';
            ROLLBACK TRANSACTION;
            GOTO Finish;
        END

        IF @Action = 1 -- INSERT
        BEGIN
            INSERT INTO [dbo].[employees] (
                companyId, firstName, lastName, email, phoneNumber, address,
                employmentTypeId, position, departmentId, statusId, hireDate, endDate,
                emergencyContactName, emergencyContactRelationship, emergencyContactPhone,
                notes, createdAt
            )
            SELECT
                companyId, firstName, lastName, email, phoneNumber, address,
                employmentTypeId, position, departmentId, statusId, hireDate, endDate,
                emergencyContactName, emergencyContactRelationship, emergencyContactPhone,
                notes, GETDATE()
            FROM @payload;

            SET @employeeId = SCOPE_IDENTITY();
            SET @Outputmessage = '{"status": "success", "message": "Employee inserted successfully."}';
        END
        ELSE IF @Action = 2 -- UPDATE
        BEGIN
            UPDATE e
            SET e.firstName = p.firstName,
                e.lastName = p.lastName,
                e.email = p.email,
                e.phoneNumber = p.phoneNumber,
                e.address = p.address,
                e.employmentTypeId = p.employmentTypeId,
                e.position = p.position,
                e.departmentId = p.departmentId,
                e.statusId = p.statusId,
                e.hireDate = p.hireDate,
                e.endDate = p.endDate,
                e.emergencyContactName = p.emergencyContactName,
                e.emergencyContactRelationship = p.emergencyContactRelationship,
                e.emergencyContactPhone = p.emergencyContactPhone,
                e.notes = p.notes,
                e.updated_at = GETDATE()
            FROM [dbo].[employees] e
            JOIN @payload p ON e.employeeId = p.employeeId AND e.companyId = p.companyId;

            SET @Outputmessage = '{"status": "success", "message": "Employee updated successfully."}';
        END
        ELSE IF @Action = 3 -- DELETE
        BEGIN
            IF EXISTS (SELECT 1 FROM [dbo].[expenses] WHERE employeeId = @employeeId)
               OR EXISTS (SELECT 1 FROM [dbo].[employeeProjectAssignments] WHERE employeeId = @employeeId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Employee has payroll or project history; set status Inactive instead of deleting."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            DELETE FROM [dbo].[employees]
            WHERE employeeId = @employeeId AND companyId = @companyId;

            SET @Outputmessage = '{"status": "success", "message": "Employee deleted successfully."}';
        END
        ELSE
        BEGIN
            SET @Outputmessage = '{"status": "error", "message": "Invalid action specified."}';
            ROLLBACK TRANSACTION;
            GOTO Finish;
        END

        COMMIT TRANSACTION;
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.value', CAST(@employeeId AS NVARCHAR(20)));
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE();
        SET @Outputmessage = (
            SELECT 'error' AS [status], 'Internal SP Error: ' + @ErrMessage AS [message]
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
    END CATCH

Finish:
    SELECT @Outputmessage AS [jsonResult];
END;
GO

-- =============================================================================
-- sp_employees_all — one company's employees, ids + display names
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_employees_all]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    -- DECLARE @pjsonfile VARCHAR(MAX) = '{"employees": [{"companyId": 1008}]}'

    DECLARE @companyId INT = (
        SELECT TOP 1 TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT)
        FROM OPENJSON(@pjsonfile, '$.employees')
    );

    -- No companyId → empty list, never "every company" (sp_suppliers_all's
    -- OR @companyId IS NULL fallback is exactly the leak this fixes).
    SELECT
        e.employeeId,
        e.companyId,
        e.firstName,
        e.lastName,
        e.email,
        ISNULL(e.phoneNumber, '') AS phoneNumber,
        ISNULL(e.address, '') AS address,
        e.employmentTypeId,
        ISNULL(et.employmentType, '') AS employmentType,
        ISNULL(e.position, '') AS position,
        e.departmentId,
        ISNULL(d.departmentName, '') AS departmentName,
        e.statusId,
        ISNULL(s.status, '') AS status,
        ISNULL(CONVERT(VARCHAR(10), e.hireDate, 23), '') AS hireDate,
        ISNULL(CONVERT(VARCHAR(10), e.endDate, 23), '') AS endDate,
        ISNULL(e.emergencyContactName, '') AS emergencyContactName,
        ISNULL(e.emergencyContactRelationship, '') AS emergencyContactRelationship,
        ISNULL(e.emergencyContactPhone, '') AS emergencyContactPhone,
        ISNULL(e.notes, '') AS notes,
        CONVERT(VARCHAR(30), e.createdAt, 126) AS createdAt,
        ISNULL(CONVERT(VARCHAR(30), e.updated_at, 126), '') AS updated_at
    FROM [dbo].[employees] e
    LEFT JOIN [dbo].[employmentTypes] et ON et.employmentTypeId = e.employmentTypeId
    LEFT JOIN [dbo].[departments] d      ON d.departmentId = e.departmentId
    LEFT JOIN [dbo].[status] s           ON s.statusId = e.statusId
    WHERE e.companyId = @companyId
    ORDER BY e.firstName, e.lastName
    FOR JSON PATH, ROOT('employees');
END;
GO

-- =============================================================================
-- sp_employees_one — one employee of one company
-- =============================================================================
CREATE OR ALTER PROCEDURE [dbo].[sp_employees_one]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    -- DECLARE @pjsonfile VARCHAR(MAX) = '{"employees": [{"companyId": 1008, "employeeId": 1}]}'

    DECLARE @companyId INT, @employeeId INT;
    SELECT TOP 1
        @companyId  = TRY_CAST(JSON_VALUE(value, '$.companyId') AS INT),
        @employeeId = TRY_CAST(JSON_VALUE(value, '$.employeeId') AS INT)
    FROM OPENJSON(@pjsonfile, '$.employees');

    SELECT
        e.employeeId,
        e.companyId,
        e.firstName,
        e.lastName,
        e.email,
        ISNULL(e.phoneNumber, '') AS phoneNumber,
        ISNULL(e.address, '') AS address,
        e.employmentTypeId,
        ISNULL(et.employmentType, '') AS employmentType,
        ISNULL(e.position, '') AS position,
        e.departmentId,
        ISNULL(d.departmentName, '') AS departmentName,
        e.statusId,
        ISNULL(s.status, '') AS status,
        ISNULL(CONVERT(VARCHAR(10), e.hireDate, 23), '') AS hireDate,
        ISNULL(CONVERT(VARCHAR(10), e.endDate, 23), '') AS endDate,
        ISNULL(e.emergencyContactName, '') AS emergencyContactName,
        ISNULL(e.emergencyContactRelationship, '') AS emergencyContactRelationship,
        ISNULL(e.emergencyContactPhone, '') AS emergencyContactPhone,
        ISNULL(e.notes, '') AS notes,
        CONVERT(VARCHAR(30), e.createdAt, 126) AS createdAt,
        ISNULL(CONVERT(VARCHAR(30), e.updated_at, 126), '') AS updated_at
    FROM [dbo].[employees] e
    LEFT JOIN [dbo].[employmentTypes] et ON et.employmentTypeId = e.employmentTypeId
    LEFT JOIN [dbo].[departments] d      ON d.departmentId = e.departmentId
    LEFT JOIN [dbo].[status] s           ON s.statusId = e.statusId
    WHERE e.employeeId = @employeeId AND e.companyId = @companyId
    FOR JSON PATH, ROOT('employees');
END;
GO
