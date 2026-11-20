/* sp_addresses / sp_addresses_all / sp_addresses_one — client addresses by source (ine / gps).
   Written by hand (the posgmo-factory couldn't handle reusing the 2024 dbo.addresses table).
   Run AFTER sql/migrations/2026-11-20_addresses_kyc_sources.sql (see its header for why and
   who calls what). Run on DEV first, then QA, then PROD. Idempotent (CREATE OR ALTER).
   Rollback: sql/migrations/2026-11-20_addresses_kyc_sources_ROLLBACK.sql. */

-- {"addresses": [{"action": 1, "companyId", "clientId", "source": "ine"|"gps", "fullAddress",
--                 "clientFaceRecognitionId"?, "street"?, "postalCode"?, "city"?, "state"?,
--                 "latitude"?, "longitude"?, "accuracyMeters"?}]}
--   action 1 = upsert the ACTIVE row of (companyId, clientId, source): updates it when it
--              exists (every field is replaced, so a gps row never keeps old coordinates),
--              inserts it otherwise.
-- {"addresses": [{"action": 3, "companyId", "clientId", "addressId"}]}
--   action 3 = deactivate (isActive = 0); rows are never deleted.
-- Returns one row: value (addressId), msg, error ('' or '1').
CREATE OR ALTER PROCEDURE [dbo].[sp_addresses]
    @pjsonfile NVARCHAR(MAX)
AS
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Outputmessage NVARCHAR(MAX) = '{"result":[{"value":"","msg":"","error":""}]}';

BEGIN TRY
    DECLARE @rowJson NVARCHAR(MAX);
    SELECT TOP 1 @rowJson = value FROM OPENJSON(@pjsonfile, '$.addresses');

    DECLARE @action INT          = TRY_CONVERT(INT, JSON_VALUE(@rowJson, '$.action')),
            @id INT              = TRY_CONVERT(INT, JSON_VALUE(@rowJson, '$.addressId')),
            @companyId INT       = TRY_CONVERT(INT, JSON_VALUE(@rowJson, '$.companyId')),
            @clientId INT        = TRY_CONVERT(INT, JSON_VALUE(@rowJson, '$.clientId')),
            @cfrId INT           = TRY_CONVERT(INT, JSON_VALUE(@rowJson, '$.clientFaceRecognitionId')),
            @source NVARCHAR(20) = LOWER(LTRIM(RTRIM(JSON_VALUE(@rowJson, '$.source')))),
            @fullAddress NVARCHAR(500) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@rowJson, '$.fullAddress'))), ''),
            @street VARCHAR(500)       = NULLIF(LTRIM(RTRIM(JSON_VALUE(@rowJson, '$.street'))), ''),
            @postalCode VARCHAR(10)    = NULLIF(LTRIM(RTRIM(JSON_VALUE(@rowJson, '$.postalCode'))), ''),
            @city VARCHAR(200)         = NULLIF(LTRIM(RTRIM(JSON_VALUE(@rowJson, '$.city'))), ''),
            @state VARCHAR(200)        = NULLIF(LTRIM(RTRIM(JSON_VALUE(@rowJson, '$.state'))), ''),
            @latitude DECIMAL(9,6)     = TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(@rowJson, '$.latitude')),
            @longitude DECIMAL(9,6)    = TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(@rowJson, '$.longitude')),
            @accuracy DECIMAL(9,2)     = TRY_CONVERT(DECIMAL(9,2), JSON_VALUE(@rowJson, '$.accuracyMeters'));

    IF @action = 1
    BEGIN
        IF @companyId IS NULL OR @clientId IS NULL
            THROW 50001, 'companyId y clientId son obligatorios.', 1;
        IF @source IS NULL OR @source NOT IN ('ine', 'gps')
            THROW 50002, 'source debe ser ine o gps.', 1;
        IF @fullAddress IS NULL
            THROW 50003, 'El domicilio está vacío.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.clients WHERE clientId = @clientId)
            THROW 50004, 'Cliente no encontrado.', 1;
        -- The KYC record must be this client's, in this company.
        IF @cfrId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.clientFaceRecognitions
                                              WHERE clientFaceRecognitionId = @cfrId
                                                AND companyId = @companyId AND clientId = @clientId)
            SET @cfrId = NULL;
        -- Coordinates only belong to the gps row.
        IF @source = 'ine'
            SELECT @latitude = NULL, @longitude = NULL, @accuracy = NULL;

        BEGIN TRANSACTION;
            SELECT @id = addressId
            FROM dbo.addresses WITH (UPDLOCK, HOLDLOCK)
            WHERE companyId = @companyId AND clientId = @clientId AND source = @source AND isActive = 1;

            IF @id IS NOT NULL
            BEGIN
                UPDATE dbo.addresses SET
                    clientFaceRecognitionId = @cfrId,
                    fullAddress = @fullAddress,
                    street = @street, postalCode = @postalCode, city = @city, state = @state,
                    latitude = @latitude, longitude = @longitude, accuracyMeters = @accuracy,
                    updatedAt = SYSUTCDATETIME()
                WHERE addressId = @id;
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Domicilio actualizado');
            END
            ELSE
            BEGIN
                INSERT INTO dbo.addresses
                    (companyId, clientId, clientFaceRecognitionId, source, fullAddress, street, postalCode,
                     city, state, latitude, longitude, accuracyMeters, isActive, createdAt)
                VALUES (@companyId, @clientId, @cfrId, @source, @fullAddress, @street, @postalCode,
                        @city, @state, @latitude, @longitude, @accuracy, 1, SYSUTCDATETIME());
                SET @id = SCOPE_IDENTITY();
                SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Domicilio guardado');
            END
        COMMIT TRANSACTION;
    END
    ELSE IF @action = 3
    BEGIN
        UPDATE dbo.addresses SET isActive = 0, updatedAt = SYSUTCDATETIME()
        WHERE addressId = @id AND companyId = @companyId AND clientId = @clientId AND isActive = 1;
        IF @@ROWCOUNT = 0 THROW 50005, 'Domicilio no encontrado.', 1;
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Domicilio desactivado');
    END
    ELSE
        THROW 50000, 'Acción no válida (1 guardar, 3 desactivar).', 1;

    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CAST(@id AS NVARCHAR(20)));
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
    SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
END CATCH;

SELECT JSON_VALUE(value, '$.value') AS value,
       JSON_VALUE(value, '$.msg')   AS msg,
       JSON_VALUE(value, '$.error') AS error
FROM OPENJSON(@Outputmessage, '$.result');
GO

-- {"addresses": [{"companyId", "clientId"}]} -> {"addresses": [ active rows of that client, ine first ]}
CREATE OR ALTER PROCEDURE [dbo].[sp_addresses_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.addresses[0].companyId')),
            @clientId INT  = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.addresses[0].clientId'));

    SELECT
        addressId,
        companyId,
        clientId,
        clientFaceRecognitionId,
        source,
        fullAddress,
        ISNULL(street, '')     AS street,
        ISNULL(postalCode, '') AS postalCode,
        ISNULL(city, '')       AS city,
        ISNULL(state, '')      AS state,
        latitude,
        longitude,
        accuracyMeters,
        CONVERT(VARCHAR(30), createdAt, 126) AS createdAt,
        ISNULL(CONVERT(VARCHAR(30), updatedAt, 126), '') AS updatedAt
    FROM dbo.addresses
    WHERE companyId = @companyId AND clientId = @clientId AND isActive = 1
    ORDER BY CASE source WHEN 'ine' THEN 0 ELSE 1 END
    FOR JSON PATH, ROOT('addresses'), INCLUDE_NULL_VALUES;
END
GO

-- {"addresses": [{"companyId", "clientId", "addressId"}]} -> {"addresses": [ that row ]}
CREATE OR ALTER PROCEDURE [dbo].[sp_addresses_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.addresses[0].companyId')),
            @clientId INT  = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.addresses[0].clientId')),
            @id INT        = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.addresses[0].addressId'));

    SELECT
        addressId,
        companyId,
        clientId,
        clientFaceRecognitionId,
        source,
        fullAddress,
        ISNULL(street, '')     AS street,
        ISNULL(postalCode, '') AS postalCode,
        ISNULL(city, '')       AS city,
        ISNULL(state, '')      AS state,
        latitude,
        longitude,
        accuracyMeters,
        CAST(isActive AS INT)  AS isActive,
        CONVERT(VARCHAR(30), createdAt, 126) AS createdAt,
        ISNULL(CONVERT(VARCHAR(30), updatedAt, 126), '') AS updatedAt
    FROM dbo.addresses
    WHERE addressId = @id AND companyId = @companyId AND clientId = @clientId
    FOR JSON PATH, ROOT('addresses'), INCLUDE_NULL_VALUES;
END
GO
