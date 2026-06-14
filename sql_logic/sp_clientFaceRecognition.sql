CREATE TABLE dbo.clientFaceRecognitions (
    clientFaceRecognitionId INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    companyId INT NOT NULL,
    documentType NVARCHAR(255) NOT NULL,
    idFrontImageBlobUrl NVARCHAR(255) NOT NULL,
    clientSelfieBlobUrl NVARCHAR(255) NOT NULL,
    confidenceScore DECIMAL(5,4) NOT NULL,
    isVerified BIT NOT NULL,
    contractAccepted BIT NOT NULL,
    acceptedAt DATETIME NOT NULL,
    created_At DATETIME NOT NULL DEFAULT GETUTCDATE(),
    updated_at DATETIME
);
GO

CREATE PROCEDURE dbo.sp_clientFaceRecognitions
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Outputmessage VARCHAR(MAX);
    BEGIN TRY
        -- Define a payload table variable to hold the parsed JSON data
        DECLARE @payload TABLE (
            action INT,
            clientFaceRecognitionId INT,
            companyId INT,
            documentType NVARCHAR(255),
            idFrontImageBlobUrl NVARCHAR(255),
            clientSelfieBlobUrl NVARCHAR(255),
            confidenceScore DECIMAL(5,4),
            isVerified BIT,
            contractAccepted BIT,
            acceptedAt DATETIME,
            contractPdfBlobUrl NVARCHAR(255) -- Added based on backend module logic
        );

        -- Insert data from JSON into the payload table
        INSERT INTO @payload (
            action,
            clientFaceRecognitionId,
            companyId,
            documentType,
            idFrontImageBlobUrl,
            clientSelfieBlobUrl,
            confidenceScore,
            isVerified,
            contractAccepted,
            acceptedAt,
            contractPdfBlobUrl
        )
        SELECT
            TRY_CONVERT(INT, JSON_VALUE(value, '$.action')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.clientFaceRecognitionId')),
            TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            JSON_VALUE(value, '$.documentType'),
            JSON_VALUE(value, '$.idFrontImageBlobUrl'),
            JSON_VALUE(value, '$.clientSelfieBlobUrl'),
            TRY_CONVERT(DECIMAL(5,4), JSON_VALUE(value, '$.confidenceScore')),
            TRY_CONVERT(BIT, JSON_VALUE(value, '$.isVerified')),
            TRY_CONVERT(BIT, JSON_VALUE(value, '$.contractAccepted')),
            TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.acceptedAt')),
            JSON_VALUE(value, '$.contractPdfBlobUrl')
        FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions');

        -- Action 1: INSERT
        IF EXISTS (SELECT 1 FROM @payload WHERE action = 1)
        BEGIN
            INSERT INTO dbo.clientFaceRecognitions (
                companyId,
                documentType,
                idFrontImageBlobUrl,
                clientSelfieBlobUrl,
                confidenceScore,
                isVerified,
                contractAccepted,
                acceptedAt,
                created_At,
                updated_at
                -- contractPdfBlobUrl is handled as an update or ignored if not in initial insert
            )
            SELECT
                p.companyId,
                p.documentType,
                p.idFrontImageBlobUrl,
                p.clientSelfieBlobUrl,
                p.confidenceScore,
                p.isVerified,
                p.contractAccepted,
                p.acceptedAt,
                GETUTCDATE(),
                NULL
            FROM @payload p
            WHERE p.action = 1;

            SET @Outputmessage = (SELECT '{"message": "Insert successful", "clientFaceRecognitionId": ' + CAST(SCOPE_IDENTITY() AS VARCHAR) + '}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            GOTO Finish;
        END;

        -- Action 2: UPDATE
        IF EXISTS (SELECT 1 FROM @payload WHERE action = 2)
        BEGIN
            UPDATE cfr
            SET
                companyId = ISNULL(p.companyId, cfr.companyId),
                documentType = ISNULL(p.documentType, cfr.documentType),
                idFrontImageBlobUrl = ISNULL(p.idFrontImageBlobUrl, cfr.idFrontImageBlobUrl),
                clientSelfieBlobUrl = ISNULL(p.clientSelfieBlobUrl, cfr.clientSelfieBlobUrl),
                confidenceScore = ISNULL(p.confidenceScore, cfr.confidenceScore),
                isVerified = ISNULL(p.isVerified, cfr.isVerified),
                contractAccepted = ISNULL(p.contractAccepted, cfr.contractAccepted),
                acceptedAt = ISNULL(p.acceptedAt, cfr.acceptedAt),
                contractPdfBlobUrl = ISNULL(p.contractPdfBlobUrl, cfr.contractPdfBlobUrl),
                updated_at = GETUTCDATE()
            FROM dbo.clientFaceRecognitions cfr
            INNER JOIN @payload p ON cfr.clientFaceRecognitionId = p.clientFaceRecognitionId
            WHERE p.action = 2;

            SET @Outputmessage = '{"message": "Update successful"}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
            GOTO Finish;
        END;

        -- Action 3: DELETE
        IF EXISTS (SELECT 1 FROM @payload WHERE action = 3)
        BEGIN
            DELETE cfr
            FROM dbo.clientFaceRecognitions cfr
            INNER JOIN @payload p ON cfr.clientFaceRecognitionId = p.clientFaceRecognitionId
            WHERE p.action = 3;

            SET @Outputmessage = '{"message": "Delete successful"}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
            GOTO Finish;
        END;

        SET @Outputmessage = '{"error": "No valid action specified."}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;

    Finish:
        SELECT @Outputmessage AS result;

    END TRY
    BEGIN CATCH
        SET @Outputmessage = (SELECT '{"error": "SQL Error: ' + ERROR_MESSAGE() + '", "errorCode": ' + CAST(ERROR_NUMBER() AS VARCHAR) + '}' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        SELECT @Outputmessage AS result;
    END CATCH
END;
GO

CREATE PROCEDURE dbo.sp_clientFaceRecognitions_all
    @pjsonfile VARCHAR(MAX) = NULL -- Added for consistency, but not strictly used for ALL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @companyId INT;

    IF @pjsonfile IS NOT NULL
    BEGIN
        SELECT @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId'))
        FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions');
    END;

    SELECT
        clientFaceRecognitionId,
        companyId,
        documentType,
        idFrontImageBlobUrl,
        clientSelfieBlobUrl,
        confidenceScore,
        isVerified,
        contractAccepted,
        CONVERT(VARCHAR(30), acceptedAt, 126) AS acceptedAt,
        CONVERT(VARCHAR(30), created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.clientFaceRecognitions
    WHERE companyId = @companyId OR @companyId IS NULL
    FOR JSON AUTO, ROOT('clientFaceRecognitions');
END;
GO

CREATE PROCEDURE dbo.sp_clientFaceRecognitions_one
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @clientFaceRecognitionId INT;
    DECLARE @companyId INT;

    SELECT
        @clientFaceRecognitionId = TRY_CONVERT(INT, JSON_VALUE(value, '$.clientFaceRecognitionId')),
        @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId'))
    FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions');

    SELECT
        clientFaceRecognitionId,
        companyId,
        documentType,
        idFrontImageBlobUrl,
        clientSelfieBlobUrl,
        confidenceScore,
        isVerified,
        contractAccepted,
        CONVERT(VARCHAR(30), acceptedAt, 126) AS acceptedAt,
        CONVERT(VARCHAR(30), created_At, 126) AS created_At,
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.clientFaceRecognitions
    WHERE clientFaceRecognitionId = @clientFaceRecognitionId AND companyId = @companyId
    FOR JSON AUTO, ROOT('clientFaceRecognitions');
END;