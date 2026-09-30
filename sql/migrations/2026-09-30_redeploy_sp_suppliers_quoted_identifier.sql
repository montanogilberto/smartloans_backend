-- =============================================================================
-- Fix: POST /suppliers returns 500 on every call (create/update/delete)
-- =============================================================================
-- Forward-only migration. NOT YET EXECUTED — run manually against the live DB.
--
-- WHY: verified 2026-09-30, even a no-op call (action=9) fails with
--   (1934) "INSERT failed because the following SET options have incorrect
--   settings: 'QUOTED_IDENTIFIER'".
-- A procedure keeps the QUOTED_IDENTIFIER/ANSI_NULLS values that were active
-- when it was CREATEd, not the caller's. sp_suppliers was created with
-- QUOTED_IDENTIFIER OFF, which SQL Server rejects for the JSON functions
-- (JSON_VALUE/OPENJSON) and for DML against tables with filtered indexes.
-- sp_suppliers_all/_one are unaffected (GET-style reads work).
--
-- WHAT: re-creates sp_suppliers with both options ON. Body is byte-for-byte
-- the one in sql/migration/02_programmability.sql — no logic change.
-- Check afterwards:
--   SELECT uses_quoted_identifier, uses_ansi_nulls
--   FROM sys.sql_modules WHERE object_id = OBJECT_ID('dbo.sp_suppliers');  -- 1, 1
-- Idempotent: CREATE OR ALTER.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[sp_suppliers]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Outputmessage VARCHAR(MAX);
    DECLARE @Action INT;

    -- Temporary table to hold the parsed JSON data
    DECLARE @payload TABLE (
        action INT,
        supplierId INT,
        companyId INT,
        supplierName NVARCHAR(200),
        contactName NVARCHAR(100),
        phone NVARCHAR(20),
        email NVARCHAR(100),
        address NVARCHAR(MAX),
        active NVARCHAR(1)
    );

    -- Ajustado el path a '$.suppliers' o '$' según envíes el objeto desde FastAPI
    INSERT INTO @payload (action, supplierId, companyId, supplierName, contactName, phone, email, address, active)
    SELECT
        JSON_VALUE(value, '$.action'),
        JSON_VALUE(value, '$.supplierId'),
        JSON_VALUE(value, '$.companyId'),
        JSON_VALUE(value, '$.supplierName'),
        JSON_VALUE(value, '$.contactName'),
        JSON_VALUE(value, '$.phone'),
        JSON_VALUE(value, '$.email'),
        JSON_VALUE(value, '$.address'),
        JSON_VALUE(value, '$.active')
    FROM OPENJSON(@pjsonfile, '$.suppliers');

    -- Fallback si el JSON no viene envuelto en un nodo 'suppliers'
    IF NOT EXISTS (SELECT 1 FROM @payload)
    BEGIN
        INSERT INTO @payload (action, supplierId, companyId, supplierName, contactName, phone, email, address, active)
        SELECT
            JSON_VALUE(@pjsonfile, '$.action'),
            JSON_VALUE(@pjsonfile, '$.supplierId'),
            JSON_VALUE(@pjsonfile, '$.companyId'),
            JSON_VALUE(@pjsonfile, '$.supplierName'),
            JSON_VALUE(@pjsonfile, '$.contactName'),
            JSON_VALUE(@pjsonfile, '$.phone'),
            JSON_VALUE(@pjsonfile, '$.email'),
            JSON_VALUE(@pjsonfile, '$.address'),
            JSON_VALUE(@pjsonfile, '$.active');
    END

    SELECT @Action = action FROM @payload;

    -- GUARDRAIL: Estructura de control transaccional requerida por la arquitectura
    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Action = 1 -- INSERT
        BEGIN
            -- Validate for duplicate supplier name within the same company
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.supplierName = p.supplierName)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier with this name already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate email within the same company
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.email = p.email WHERE p.email IS NOT NULL AND p.email != '')
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier with this email already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate phone within the same company
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.phone = p.phone WHERE p.phone IS NOT NULL AND p.phone != '')
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier with this phone number already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            INSERT INTO [dbo].[Suppliers] (
                companyId, supplierName, contactName, phone, email, address, active, created_At
            )
            SELECT
                companyId, supplierName, contactName, phone, email, address, active, GETDATE()
            FROM @payload;

            SET @Outputmessage = '{"status": "success", "message": "Supplier inserted successfully."}';
        END
        ELSE IF @Action = 2 -- UPDATE
        BEGIN
            -- Validate if the supplier exists
            IF NOT EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.supplierId = p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier not found."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate supplier name excluding current record
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.supplierName = p.supplierName WHERE s.supplierId != p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another supplier with this name already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate email excluding current record
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.email = p.email WHERE p.email IS NOT NULL AND p.email != '' AND s.supplierId != p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another supplier with this email already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            -- Validate for duplicate phone excluding current record
            IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.phone = p.phone WHERE p.phone IS NOT NULL AND p.phone != '' AND s.supplierId != p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Another supplier with this phone number already exists for this company."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            UPDATE s
            SET
                s.companyId = p.companyId,
                s.supplierName = p.supplierName,
                s.contactName = p.contactName,
                s.phone = p.phone,
                s.email = p.email,
                s.address = p.address,
                s.active = p.active,
                s.updated_at = GETDATE()
            FROM [dbo].[Suppliers] s
            JOIN @payload p ON s.supplierId = p.supplierId;

            SET @Outputmessage = '{"status": "success", "message": "Supplier updated successfully."}';
        END
        ELSE IF @Action = 3 -- DELETE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.supplierId = p.supplierId)
            BEGIN
                SET @Outputmessage = '{"status": "error", "message": "Supplier not found."}';
                ROLLBACK TRANSACTION;
                GOTO Finish;
            END

            DELETE s
            FROM [dbo].[Suppliers] s
            JOIN @payload p ON s.supplierId = p.supplierId;

            SET @Outputmessage = '{"status": "success", "message": "Supplier deleted successfully."}';
        END
        ELSE
        BEGIN
            SET @Outputmessage = '{"status": "error", "message": "Invalid action specified."}';
            ROLLBACK TRANSACTION;
            GOTO Finish;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @ErrMessage NVARCHAR(4000) = ERROR_MESSAGE();
        SET @Outputmessage = (
            SELECT 
                'error' AS [status], 
                'Internal SP Error: ' + @ErrMessage AS [message] 
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
    END CATCH

Finish:
    -- Retorna exactamente una fila con una columna '[jsonResult]', ideal para tu backend en FastAPI (json_result[0][0])
    SELECT @Outputmessage AS [jsonResult];
END;
GO
