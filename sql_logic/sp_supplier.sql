CREATE TABLE dbo.Suppliers (
    supplierId int IDENTITY(1,1) NOT NULL,
    companyId int NOT NULL,
    supplierName nvarchar(200) NOT NULL,
    contactName nvarchar(100) NULL,
    phone nvarchar(20) NULL,
    email nvarchar(100) NULL,
    address nvarchar(MAX) NULL,
    active nvarchar(1) NOT NULL,
    createdAt datetime NOT NULL DEFAULT GETDATE(),
    updatedAt datetime NULL,
    CONSTRAINT PK_Suppliers PRIMARY KEY CLUSTERED (supplierId ASC),
    CONSTRAINT FK_Suppliers_Companies FOREIGN KEY (companyId) REFERENCES dbo.companies(companyId)
);

CREATE NONCLUSTERED INDEX IX_Suppliers_supplierName ON dbo.Suppliers(supplierName);
GO
CREATE OR ALTER PROCEDURE dbo.sp_supplier
    @pjsonfile nvarchar(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @action nvarchar(50);
    DECLARE @supplierId int;
    DECLARE @companyId int;
    DECLARE @supplierName nvarchar(200);
    DECLARE @contactName nvarchar(100);
    DECLARE @phone nvarchar(20);
    DECLARE @email nvarchar(100);
    DECLARE @address nvarchar(MAX);
    DECLARE @active nvarchar(1);

    SELECT
        @action = JSON_VALUE(@pjsonfile, '$.action'),
        @supplierId = JSON_VALUE(@pjsonfile, '$.supplierId'),
        @companyId = JSON_VALUE(@pjsonfile, '$.companyId'),
        @supplierName = JSON_VALUE(@pjsonfile, '$.supplierName'),
        @contactName = JSON_VALUE(@pjsonfile, '$.contactName'),
        @phone = JSON_VALUE(@pjsonfile, '$.phone'),
        @email = JSON_VALUE(@pjsonfile, '$.email'),
        @address = JSON_VALUE(@pjsonfile, '$.address'),
        @active = JSON_VALUE(@pjsonfile, '$.active');

    BEGIN TRY
        BEGIN TRAN;

        IF @action = 'INSERT'
        BEGIN
            INSERT INTO dbo.Suppliers (companyId, supplierName, contactName, phone, email, address, active, createdAt, updatedAt)
            VALUES (@companyId, @supplierName, @contactName, @phone, @email, @address, @active, GETDATE(), NULL);

            SELECT * FROM dbo.Suppliers WHERE supplierId = SCOPE_IDENTITY() FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        END
        ELSE IF @action = 'UPDATE'
        BEGIN
            UPDATE dbo.Suppliers
            SET
                supplierName = @supplierName,
                contactName = @contactName,
                phone = @phone,
                email = @email,
                address = @address,
                active = @active,
                updatedAt = GETDATE()
            WHERE supplierId = @supplierId AND companyId = @companyId;

            SELECT * FROM dbo.Suppliers WHERE supplierId = @supplierId AND companyId = @companyId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        END;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        THROW;
    END CATCH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_supplier_all
    @pjsonfile nvarchar(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId int;

    SELECT @companyId = JSON_VALUE(@pjsonfile, '$.companyId');

    SELECT
        supplierId,
        companyId,
        supplierName,
        contactName,
        phone,
        email,
        address,
        active,
        createdAt,
        updatedAt
    FROM dbo.Suppliers
    WHERE companyId = @companyId
    FOR JSON PATH;
END;
GO
CREATE OR ALTER PROCEDURE dbo.sp_supplier_one
    @pjsonfile nvarchar(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @supplierId int;
    DECLARE @companyId int;

    SELECT
        @supplierId = JSON_VALUE(@pjsonfile, '$.supplierId'),
        @companyId = JSON_VALUE(@pjsonfile, '$.companyId');

    SELECT
        supplierId,
        companyId,
        supplierName,
        contactName,
        phone,
        email,
        address,
        active,
        createdAt,
        updatedAt
    FROM dbo.Suppliers
    WHERE supplierId = @supplierId AND companyId = @companyId
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END;