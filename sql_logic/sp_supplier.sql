CREATE TABLE [dbo].[Suppliers] (
  [supplierId] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
  [companyId] INT NOT NULL,
  [supplierName] NVARCHAR(200) NOT NULL,
  [contactName] NVARCHAR(100),
  [phone] NVARCHAR(20),
  [email] NVARCHAR(100),
  [address] NVARCHAR(MAX),
  [active] NVARCHAR(1) NOT NULL,
  [created_At] DATETIME NOT NULL DEFAULT GETDATE(),
  [updated_at] DATETIME,
  FOREIGN KEY ([companyId]) REFERENCES [dbo].[companies]([companyId])
);

CREATE INDEX IX_Suppliers_CompanyId ON [dbo].[Suppliers] ([companyId]);
CREATE INDEX IX_Suppliers_SupplierName ON [dbo].[Suppliers] ([supplierName]);
CREATE UNIQUE NONCLUSTERED INDEX UQ_Suppliers_Email_CompanyId ON [dbo].[Suppliers] ([email], [companyId]) WHERE [email] IS NOT NULL;
CREATE UNIQUE NONCLUSTERED INDEX UQ_Suppliers_Phone_CompanyId ON [dbo].[Suppliers] ([phone], [companyId]) WHERE [phone] IS NOT NULL;
GO

CREATE PROCEDURE [dbo].[sp_suppliers]
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

    SELECT @Action = action FROM @payload;

    IF @Action = 1 -- INSERT
    BEGIN
        -- Validate for duplicate supplier name within the same company
        IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.supplierName = p.supplierName WHERE p.action = 1)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Supplier with this name already exists for this company."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        -- Validate for duplicate email within the same company (if email is provided)
        IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.email = p.email WHERE p.action = 1 AND p.email IS NOT NULL AND p.email != '')
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Supplier with this email already exists for this company."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        -- Validate for duplicate phone within the same company (if phone is provided)
        IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.phone = p.phone WHERE p.action = 1 AND p.phone IS NOT NULL AND p.phone != '')
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Supplier with this phone number already exists for this company."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        INSERT INTO [dbo].[Suppliers] (
            companyId, supplierName, contactName, phone, email, address, active, created_At
        )
        SELECT
            companyId, supplierName, contactName, phone, email, address, active, GETDATE()
        FROM @payload
        WHERE action = 1;

        SET @Outputmessage = (SELECT '{{"status": "success", "message": "Supplier inserted successfully."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE IF @Action = 2 -- UPDATE
    BEGIN
        -- Validate if the supplier exists
        IF NOT EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.supplierId = p.supplierId WHERE p.action = 2)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Supplier not found."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        -- Validate for duplicate supplier name within the same company, excluding the current supplier
        IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.supplierName = p.supplierName WHERE p.action = 2 AND s.supplierId != p.supplierId)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Another supplier with this name already exists for this company."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        -- Validate for duplicate email within the same company, excluding the current supplier (if email is provided)
        IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.email = p.email WHERE p.action = 2 AND p.email IS NOT NULL AND p.email != '' AND s.supplierId != p.supplierId)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Another supplier with this email already exists for this company."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        -- Validate for duplicate phone within the same company, excluding the current supplier (if phone is provided)
        IF EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.companyId = p.companyId AND s.phone = p.phone WHERE p.action = 2 AND p.phone IS NOT NULL AND p.phone != '' AND s.supplierId != p.supplierId)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Another supplier with this phone number already exists for this company."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
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
        JOIN @payload p ON s.supplierId = p.supplierId
        WHERE p.action = 2;

        SET @Outputmessage = (SELECT '{{"status": "success", "message": "Supplier updated successfully."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE IF @Action = 3 -- DELETE
    BEGIN
        -- Validate if the supplier exists
        IF NOT EXISTS (SELECT 1 FROM [dbo].[Suppliers] s JOIN @payload p ON s.supplierId = p.supplierId WHERE p.action = 3)
        BEGIN
            SET @Outputmessage = (SELECT '{{"status": "error", "message": "Supplier not found."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END

        DELETE s
        FROM [dbo].[Suppliers] s
        JOIN @payload p ON s.supplierId = p.supplierId
        WHERE p.action = 3;

        SET @Outputmessage = (SELECT '{{"status": "success", "message": "Supplier deleted successfully."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END
    ELSE
    BEGIN
        SET @Outputmessage = (SELECT '{{"status": "error", "message": "Invalid action specified."}}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    END

Finish:
    SELECT @Outputmessage AS [jsonResult];
END;
GO

CREATE PROCEDURE [dbo].[sp_suppliers_all]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @companyId INT;

    SELECT @companyId = JSON_VALUE(value, '$.companyId')
    FROM OPENJSON(@pjsonfile, '$.plural')
    WHERE JSON_VALUE(value, '$.companyId') IS NOT NULL;

    SELECT
        s.supplierId,
        s.companyId,
        s.supplierName,
        ISNULL(s.contactName, '') AS contactName,
        ISNULL(s.phone, '') AS phone,
        ISNULL(s.email, '') AS email,
        ISNULL(s.address, '') AS address,
        s.active,
        CONVERT(VARCHAR(30), s.created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), s.updated_at, 126), '') AS updated_at
    FROM [dbo].[Suppliers] s
    WHERE s.companyId = @companyId OR @companyId IS NULL
    FOR JSON AUTO, ROOT('suppliers');
END;
GO

CREATE PROCEDURE [dbo].[sp_suppliers_one]
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @supplierId INT;
    DECLARE @companyId INT;

    SELECT
        @supplierId = JSON_VALUE(@pjsonfile, '$.supplierId'),
        @companyId = JSON_VALUE(@pjsonfile, '$.companyId');

    SELECT
        s.supplierId,
        s.companyId,
        s.supplierName,
        ISNULL(s.contactName, '') AS contactName,
        ISNULL(s.phone, '') AS phone,
        ISNULL(s.email, '') AS email,
        ISNULL(s.address, '') AS address,
        s.active,
        CONVERT(VARCHAR(30), s.created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), s.updated_at, 126), '') AS updated_at
    FROM [dbo].[Suppliers] s
    WHERE s.supplierId = @supplierId AND s.companyId = @companyId
    FOR JSON AUTO, ROOT('suppliers');
END;