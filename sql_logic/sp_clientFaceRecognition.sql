CREATE TABLE dbo.ClientFaceRecognitions (
    clientFaceRecognitionId INT IDENTITY(1,1) NOT NULL,
    companyId INT NOT NULL,
    document_type NVARCHAR(50) NOT NULL,
    id_front_image_blob_url NVARCHAR(500) NOT NULL,
    client_selfie_blob_url NVARCHAR(500) NOT NULL,
    confidence_score DECIMAL(5,4) NOT NULL,
    is_verified BIT NOT NULL,
    contract_accepted BIT NOT NULL,
    accepted_at DATETIME NOT NULL,
    created_At DATETIME NOT NULL DEFAULT GETDATE(),
    updated_at DATETIME NULL,
    CONSTRAINT PK_ClientFaceRecognitions PRIMARY KEY CLUSTERED (clientFaceRecognitionId ASC),
    CONSTRAINT FK_ClientFaceRecognitions_Companies FOREIGN KEY (companyId) REFERENCES dbo.companies(companyId)
);
GO

CREATE NONCLUSTERED INDEX IX_ClientFaceRecognitions_CompanyId ON dbo.ClientFaceRecognitions (companyId);
GO
CREATE NONCLUSTERED INDEX IX_ClientFaceRecognitions_ConfidenceScore ON dbo.ClientFaceRecognitions (confidence_score);
GO
CREATE NONCLUSTERED INDEX IX_ClientFaceRecognitions_Created_At ON dbo.ClientFaceRecognitions (created_At);
GO
CREATE NONCLUSTERED INDEX IX_ClientFaceRecognitions_document_type ON dbo.ClientFaceRecognitions (document_type);
GO
CREATE NONCLUSTERED INDEX IX_ClientFaceRecognitions_is_verified ON dbo.ClientFaceRecognitions (is_verified);
GO
CREATE NONCLUSTERED INDEX IX_ClientFaceRecognitions_contract_accepted ON dbo.ClientFaceRecognitions (contract_accepted);
GO
CREATE NONCLUSTERED INDEX IX_ClientFaceRecognitions_accepted_at ON dbo.ClientFaceRecognitions (accepted_at);
GO

CREATE OR ALTER PROC [dbo].[sp_clientFaceRecognitions] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @Outputmessage NVARCHAR(MAX) = '{
      "result": [
        {{ "value": "", "msg": "", "error": "" }}
      ]
    }';
    DECLARE @action INT;

    SET @action = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions')
    );

    DECLARE @payload TABLE (
        clientFaceRecognitionId  INT NULL,
        companyId                INT NULL,
        document_type            NVARCHAR(50) NULL,
        id_front_image_blob_url  NVARCHAR(500) NULL,
        client_selfie_blob_url   NVARCHAR(500) NULL,
        confidence_score         DECIMAL(5,4) NULL,
        is_verified              BIT NULL,
        contract_accepted        BIT NULL,
        accepted_at              DATETIME NULL
    );

    INSERT INTO @payload (
        clientFaceRecognitionId,
        companyId,
        document_type,
        id_front_image_blob_url,
        client_selfie_blob_url,
        confidence_score,
        is_verified,
        contract_accepted,
        accepted_at
    )
    SELECT
        TRY_CONVERT(INT, JSON_VALUE(value, '$.clientFaceRecognitionId')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        JSON_VALUE(value, '$.documentType'),
        JSON_VALUE(value, '$.idFrontImageBlobUrl'),
        JSON_VALUE(value, '$.clientSelfieBlobUrl'),
        TRY_CONVERT(DECIMAL(5,4), JSON_VALUE(value, '$.confidenceScore')),
        TRY_CONVERT(BIT, JSON_VALUE(value, '$.isVerified')),
        TRY_CONVERT(BIT, JSON_VALUE(value, '$.contractAccepted')),
        TRY_CONVERT(DATETIME, JSON_VALUE(value, '$.acceptedAt'))
    FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions');

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1 -- INSERT
        BEGIN
            -- No specific duplicate validations specified for INSERT beyond PK/FK which are handled by the DB.
            INSERT INTO dbo.ClientFaceRecognitions (
                companyId,
                document_type,
                id_front_image_blob_url,
                client_selfie_blob_url,
                confidence_score,
                is_verified,
                contract_accepted,
                accepted_at,
                created_At
            )
            SELECT
                p.companyId,
                p.document_type,
                p.id_front_image_blob_url,
                p.client_selfie_blob_url,
                p.confidence_score,
                p.is_verified,
                p.contract_accepted,
                p.accepted_at,
                GETDATE()
            FROM @payload p;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2 -- UPDATE
        BEGIN
            -- No specific duplicate validations for UPDATE beyond PK/FK which are handled by the DB.
            UPDATE cfr
            SET
                cfr.companyId               = p.companyId,
                cfr.document_type           = p.document_type,
                cfr.id_front_image_blob_url = p.id_front_image_blob_url,
                cfr.client_selfie_blob_url  = p.client_selfie_blob_url,
                cfr.confidence_score        = p.confidence_score,
                cfr.is_verified             = p.is_verified,
                cfr.contract_accepted       = p.contract_accepted,
                cfr.accepted_at             = p.accepted_at,
                cfr.updated_at              = GETDATE()
            FROM dbo.ClientFaceRecognitions cfr
            INNER JOIN @payload p ON cfr.clientFaceRecognitionId = p.clientFaceRecognitionId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3 -- DELETE
        BEGIN
            DELETE cfr
            FROM dbo.ClientFaceRecognitions cfr
            INNER JOIN @payload p ON cfr.clientFaceRecognitionId = p.clientFaceRecognitionId;

            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Deleted Successfully');
        END
        ELSE
        BEGIN
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Invalid action specified.');
        END

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].error', '1');
        SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', ERROR_MESSAGE());
    END CATCH;

Finish:
    SELECT
        JSON_VALUE(value,'$.value') AS value,
        JSON_VALUE(value,'$.msg')   AS msg,
        JSON_VALUE(value,'$.error') AS error
    FROM OPENJSON(@Outputmessage,'$.result');
END;
GO

CREATE OR ALTER PROC [dbo].[sp_clientFaceRecognitions_all] (@pjsonfile VARCHAR(MAX))
AS
SET NOCOUNT ON
BEGIN
    DECLARE @companyId INT;
    SET @companyId = TRY_CONVERT(INT,
        (SELECT TOP 1 JSON_VALUE(value, '$.companyId')
         FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions'))
    );
    SELECT
        [clientFaceRecognitionId],
        ISNULL([companyId], 0)                   AS companyId,
        ISNULL([document_type], '')              AS document_type,
        ISNULL([id_front_image_blob_url], '')    AS id_front_image_blob_url,
        ISNULL([client_selfie_blob_url], '')     AS client_selfie_blob_url,
        ISNULL([confidence_score], 0.0000)       AS confidence_score,
        ISNULL([is_verified], 0)                 AS is_verified,
        ISNULL([contract_accepted], 0)           AS contract_accepted,
        [accepted_at],
        [created_At],
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.ClientFaceRecognitions
    WHERE companyId = @companyId
    FOR JSON AUTO, ROOT('clientFaceRecognitions');
END;
GO

CREATE OR ALTER PROC [dbo].[sp_clientFaceRecognitions_one] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @clientFaceRecognitionId INT;
    SET @clientFaceRecognitionId = CAST(
        (SELECT TOP 1 JSON_VALUE(value, '$.clientFaceRecognitionId')
         FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions')) AS INT
    );
    SELECT
        clientFaceRecognitionId,
        ISNULL(companyId, 0)                   AS companyId,
        ISNULL(document_type, '')              AS document_type,
        ISNULL(id_front_image_blob_url, '')    AS id_front_image_blob_url,
        ISNULL(client_selfie_blob_url, '')     AS client_selfie_blob_url,
        ISNULL(confidence_score, 0.0000)       AS confidence_score,
        ISNULL(is_verified, 0)                 AS is_verified,
        ISNULL(contract_accepted, 0)           AS contract_accepted,
        accepted_at,
        created_At,
        ISNULL(CONVERT(VARCHAR(30), updated_at, 126), '') AS updated_at
    FROM dbo.ClientFaceRecognitions
    WHERE clientFaceRecognitionId = @clientFaceRecognitionId
    FOR JSON AUTO, ROOT('clientFaceRecognitions');
END;
GO
