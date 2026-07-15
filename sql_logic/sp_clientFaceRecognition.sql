-- Reflects the ACTUAL live schema/procs as pulled directly from the
-- database (OBJECT_DEFINITION / sys.columns) on 2026-07-15. The version of
-- this file previously checked in was badly stale — missing clientId,
-- idBackImageBlobUrl, azureSessionId, pagareAccepted, and several other
-- columns/branches that were already live and in active use. Keep this
-- file honest going forward: if you change the live SP directly (as this
-- codebase's established practice does — CREATE OR ALTER PROC applied
-- straight to the DB, verified, then documented here after), update this
-- file in the same change.

CREATE TABLE dbo.ClientFaceRecognitions (
    clientFaceRecognitionId      INT IDENTITY(1,1)   NOT NULL,
    companyId                    INT                 NOT NULL,
    clientId                     INT                 NOT NULL,
    document_type                NVARCHAR(255)       NOT NULL,
    id_front_image_blob_url      NVARCHAR(2048)      NOT NULL,
    id_back_image_blob_url       NVARCHAR(2048)      NULL,
    azure_session_id             UNIQUEIDENTIFIER    NULL,
    client_selfie_blob_url       NVARCHAR(2048)      NOT NULL,
    confidence_score             DECIMAL(5,4)        NOT NULL,
    is_verified                  BIT                 NOT NULL,

    -- Legal contract metadata
    contract_accepted            BIT                 NOT NULL,
    contract_pdf_blob_url        NVARCHAR(2048)       NULL,
    contract_accepted_at         DATETIME2(7)         NULL,
    accepted_at                  DATETIME             NOT NULL,  -- legacy NOT NULL column, superseded by contract_accepted_at but never dropped

    -- Legal pagaré metadata
    pagare_accepted               BIT                 NOT NULL,
    pagare_pdf_blob_url           NVARCHAR(2048)       NULL,
    pagare_accepted_at            DATETIME2(7)         NULL,
    has_physical_pagare           BIT                 NOT NULL,
    physical_pagare_verified_at   DATETIME2(7)         NULL,

    -- Presence capture (video + GPS), added for location/audit evidence —
    -- OCR can't reliably read a printed address off an INE (confirmed via
    -- extensive testing: the front's printed fields sit on an anti-copy
    -- watermark pattern that defeats OCR regardless of engine/resolution),
    -- so this is raw GPS + a short video as evidence instead.
    presence_video_blob_url            NVARCHAR(2048) NULL,
    presence_latitude                  DECIMAL(9,6)   NULL,
    presence_longitude                 DECIMAL(9,6)   NULL,
    presence_location_accuracy_meters  DECIMAL(9,2)   NULL,
    presence_captured_at               DATETIME2(7)   NULL,

    -- Signature match: printed ID signature vs. contract-signing signature,
    -- compared automatically (modules/signatureMatching.py) rather than
    -- just shown side-by-side for staff review.
    id_signature_crop_blob_url    NVARCHAR(2048) NULL,
    contract_signature_blob_url   NVARCHAR(2048) NULL,
    signature_match_score         DECIMAL(5,2)   NULL,
    signature_match_passed        BIT            NULL,
    signature_matched_at          DATETIME2(7)   NULL,

    -- System audit columns
    is_active                    BIT                 NOT NULL,
    created_by                   INT                 NOT NULL,
    created_At                   DATETIME             NOT NULL DEFAULT GETDATE(),
    updated_by                   INT                 NULL,
    updated_at                   DATETIME2(7)         NULL,

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
        { "value": "", "msg": "", "error": "" }
      ]
    }';
    DECLARE @action INT;
    DECLARE @resultId INT;

    SET @action = (
        SELECT TOP 1 TRY_CONVERT(INT, JSON_VALUE(value, '$.action'))
        FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions')
    );

    DECLARE @payload TABLE (
        clientFaceRecognitionId      INT NULL,
        companyId                    INT NULL,
        clientId                     INT NULL,
        document_type                NVARCHAR(50) NULL,
        id_front_image_blob_url      NVARCHAR(2048) NULL,
        id_back_image_blob_url       NVARCHAR(2048) NULL,
        azure_session_id             UNIQUEIDENTIFIER NULL,
        client_selfie_blob_url       NVARCHAR(2048) NULL,
        confidence_score             DECIMAL(5,4) NULL,
        is_verified                  BIT NULL,

        contract_accepted            BIT NULL,
        contract_pdf_blob_url        NVARCHAR(2048) NULL,
        contract_accepted_at         DATETIME2(7) NULL,

        pagare_accepted              BIT NULL,
        pagare_pdf_blob_url          NVARCHAR(2048) NULL,
        pagare_accepted_at           DATETIME2(7) NULL,
        has_physical_pagare          BIT NULL,
        physical_pagare_verified_at  DATETIME2(7) NULL,

        -- Presence capture (video + GPS), added for location/audit evidence
        presence_video_blob_url            NVARCHAR(2048) NULL,
        presence_latitude                  DECIMAL(9,6) NULL,
        presence_longitude                 DECIMAL(9,6) NULL,
        presence_location_accuracy_meters  DECIMAL(9,2) NULL,
        presence_captured_at               DATETIME2(7) NULL,

        -- Signature match (ID-crop vs contract signature)
        id_signature_crop_blob_url    NVARCHAR(2048) NULL,
        contract_signature_blob_url   NVARCHAR(2048) NULL,
        signature_match_score         DECIMAL(5,2) NULL,
        signature_match_passed        BIT NULL,
        signature_matched_at          DATETIME2(7) NULL,

        userId                       INT NULL -- Captures the operator/creator identity context
    );

    INSERT INTO @payload (
        clientFaceRecognitionId,
        companyId,
        clientId,
        document_type,
        id_front_image_blob_url,
        id_back_image_blob_url,
        azure_session_id,
        client_selfie_blob_url,
        confidence_score,
        is_verified,
        contract_accepted,
        contract_pdf_blob_url,
        contract_accepted_at,
        pagare_accepted,
        pagare_pdf_blob_url,
        pagare_accepted_at,
        has_physical_pagare,
        physical_pagare_verified_at,
        presence_video_blob_url,
        presence_latitude,
        presence_longitude,
        presence_location_accuracy_meters,
        presence_captured_at,
        id_signature_crop_blob_url,
        contract_signature_blob_url,
        signature_match_score,
        signature_match_passed,
        signature_matched_at,
        userId
    )
    SELECT
        TRY_CONVERT(INT, JSON_VALUE(value, '$.clientFaceRecognitionId')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
        JSON_VALUE(value, '$.documentType'),
        JSON_VALUE(value, '$.idFrontImageBlobUrl'),
        JSON_VALUE(value, '$.idBackImageBlobUrl'),
        TRY_CONVERT(UNIQUEIDENTIFIER, JSON_VALUE(value, '$.azureSessionId')),
        JSON_VALUE(value, '$.clientSelfieBlobUrl'),
        TRY_CONVERT(DECIMAL(5,4), JSON_VALUE(value, '$.confidenceScore')),
        TRY_CONVERT(BIT, JSON_VALUE(value, '$.isVerified')),

        TRY_CONVERT(BIT, JSON_VALUE(value, '$.contractAccepted')),
        JSON_VALUE(value, '$.contractPdfBlobUrl'),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.contractAcceptedAt')),

        TRY_CONVERT(BIT, JSON_VALUE(value, '$.pagareAccepted')),
        JSON_VALUE(value, '$.pagarePdfBlobUrl'),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.pagareAcceptedAt')),
        TRY_CONVERT(BIT, JSON_VALUE(value, '$.hasPhysicalPagare')),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.physicalPagareVerifiedAt')),

        JSON_VALUE(value, '$.presenceVideoBlobUrl'),
        TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.presenceLatitude')),
        TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.presenceLongitude')),
        TRY_CONVERT(DECIMAL(9,2), JSON_VALUE(value, '$.presenceLocationAccuracyMeters')),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.presenceCapturedAt')),

        JSON_VALUE(value, '$.idSignatureCropBlobUrl'),
        JSON_VALUE(value, '$.contractSignatureBlobUrl'),
        TRY_CONVERT(DECIMAL(5,2), JSON_VALUE(value, '$.signatureMatchScore')),
        TRY_CONVERT(BIT, JSON_VALUE(value, '$.signatureMatchPassed')),
        TRY_CONVERT(DATETIME2(7), JSON_VALUE(value, '$.signatureMatchedAt')),

        TRY_CONVERT(INT, JSON_VALUE(value, '$.userId')) -- Maps to auditing tracking values
    FROM OPENJSON(@pjsonfile, '$.clientFaceRecognitions');

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @action = 1 -- INSERT
        BEGIN
            INSERT INTO dbo.ClientFaceRecognitions (
                companyId,
                clientId,
                document_type,
                id_front_image_blob_url,
                id_back_image_blob_url,
                azure_session_id,
                client_selfie_blob_url,
                confidence_score,
                is_verified,
                contract_accepted,
                contract_pdf_blob_url,
                contract_accepted_at,
                accepted_at,
                pagare_accepted,
                pagare_pdf_blob_url,
                pagare_accepted_at,
                has_physical_pagare,
                physical_pagare_verified_at,
                presence_video_blob_url,
                presence_latitude,
                presence_longitude,
                presence_location_accuracy_meters,
                presence_captured_at,
                id_signature_crop_blob_url,
                contract_signature_blob_url,
                signature_match_score,
                signature_match_passed,
                signature_matched_at,
                is_active,
                created_by,
                created_At
            )
            SELECT
                p.companyId,
                p.clientId,
                p.document_type,
                p.id_front_image_blob_url,
                p.id_back_image_blob_url,
                p.azure_session_id,
                p.client_selfie_blob_url,
                p.confidence_score,
                p.is_verified,
                p.contract_accepted,
                p.contract_pdf_blob_url,
                p.contract_accepted_at,
                -- Legacy NOT NULL column, superseded by contract_accepted_at
                -- but never dropped. Mirror it here so inserts don't fail.
                ISNULL(p.contract_accepted_at, SYSUTCDATETIME()),
                p.pagare_accepted,
                p.pagare_pdf_blob_url,
                p.pagare_accepted_at,
                ISNULL(p.has_physical_pagare, 0),
                p.physical_pagare_verified_at,
                p.presence_video_blob_url,
                p.presence_latitude,
                p.presence_longitude,
                p.presence_location_accuracy_meters,
                p.presence_captured_at,
                p.id_signature_crop_blob_url,
                p.contract_signature_blob_url,
                p.signature_match_score,
                p.signature_match_passed,
                p.signature_matched_at,
                1, -- Defaulting row state as active
                ISNULL(p.userId, 1), -- fallback safely to system user seed
                SYSUTCDATETIME()
            FROM @payload p;

            -- Frontend needs the new row's ID back so later captures (back
            -- image, selfie, confidence score, contract) update this same
            -- row instead of silently no-op'ing or creating duplicates.
            SET @resultId = SCOPE_IDENTITY();
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(20), @resultId));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Inserted Successfully');
        END
        ELSE IF @action = 2 -- UPDATE
        BEGIN
            -- COALESCE against the existing row so a partial patch (e.g.
            -- just { clientSelfieBlobUrl } from an incremental capture step)
            -- only touches the fields it actually sent, instead of nulling
            -- out every other NOT NULL column with the JSON's absent keys.
            UPDATE cfr
            SET
                cfr.companyId                  = COALESCE(p.companyId, cfr.companyId),
                cfr.clientId                   = COALESCE(p.clientId, cfr.clientId),
                cfr.document_type              = COALESCE(p.document_type, cfr.document_type),
                cfr.id_front_image_blob_url    = COALESCE(p.id_front_image_blob_url, cfr.id_front_image_blob_url),
                cfr.id_back_image_blob_url     = COALESCE(p.id_back_image_blob_url, cfr.id_back_image_blob_url),
                cfr.azure_session_id           = COALESCE(p.azure_session_id, cfr.azure_session_id),
                cfr.client_selfie_blob_url     = COALESCE(p.client_selfie_blob_url, cfr.client_selfie_blob_url),
                cfr.confidence_score           = COALESCE(p.confidence_score, cfr.confidence_score),
                cfr.is_verified                = COALESCE(p.is_verified, cfr.is_verified),

                cfr.contract_accepted          = COALESCE(p.contract_accepted, cfr.contract_accepted),
                cfr.contract_pdf_blob_url      = COALESCE(p.contract_pdf_blob_url, cfr.contract_pdf_blob_url),
                cfr.contract_accepted_at       = COALESCE(p.contract_accepted_at, cfr.contract_accepted_at),

                cfr.pagare_accepted            = COALESCE(p.pagare_accepted, cfr.pagare_accepted),
                cfr.pagare_pdf_blob_url        = COALESCE(p.pagare_pdf_blob_url, cfr.pagare_pdf_blob_url),
                cfr.pagare_accepted_at         = COALESCE(p.pagare_accepted_at, cfr.pagare_accepted_at),
                cfr.has_physical_pagare        = COALESCE(p.has_physical_pagare, cfr.has_physical_pagare),
                cfr.physical_pagare_verified_at = COALESCE(p.physical_pagare_verified_at, cfr.physical_pagare_verified_at),

                cfr.presence_video_blob_url            = COALESCE(p.presence_video_blob_url, cfr.presence_video_blob_url),
                cfr.presence_latitude                  = COALESCE(p.presence_latitude, cfr.presence_latitude),
                cfr.presence_longitude                 = COALESCE(p.presence_longitude, cfr.presence_longitude),
                cfr.presence_location_accuracy_meters  = COALESCE(p.presence_location_accuracy_meters, cfr.presence_location_accuracy_meters),
                cfr.presence_captured_at               = COALESCE(p.presence_captured_at, cfr.presence_captured_at),

                cfr.id_signature_crop_blob_url  = COALESCE(p.id_signature_crop_blob_url, cfr.id_signature_crop_blob_url),
                cfr.contract_signature_blob_url = COALESCE(p.contract_signature_blob_url, cfr.contract_signature_blob_url),
                cfr.signature_match_score       = COALESCE(p.signature_match_score, cfr.signature_match_score),
                cfr.signature_match_passed      = COALESCE(p.signature_match_passed, cfr.signature_match_passed),
                cfr.signature_matched_at        = COALESCE(p.signature_matched_at, cfr.signature_matched_at),

                cfr.updated_by                 = COALESCE(p.userId, cfr.updated_by),
                cfr.updated_at                 = SYSUTCDATETIME()
            FROM dbo.ClientFaceRecognitions cfr
            INNER JOIN @payload p ON cfr.clientFaceRecognitionId = p.clientFaceRecognitionId;

            SELECT TOP 1 @resultId = clientFaceRecognitionId FROM @payload;
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].value', CONVERT(NVARCHAR(20), @resultId));
            SET @Outputmessage = JSON_MODIFY(@Outputmessage, '$.result[0].msg', 'Updated Successfully');
        END
        ELSE IF @action = 3 -- DELETE
        BEGIN
            -- Hard delete logic retained from your existing layout structure
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
        ISNULL([companyId], 0)                             AS companyId,
        ISNULL([clientId], 0)                              AS clientId,
        ISNULL([document_type], '')                        AS documentType,
        ISNULL([id_front_image_blob_url], '')              AS idFrontImageBlobUrl,
        ISNULL([id_back_image_blob_url], '')               AS idBackImageBlobUrl,
        [azure_session_id]                                 AS azureSessionId,
        ISNULL([client_selfie_blob_url], '')               AS clientSelfieBlobUrl,
        ISNULL([confidence_score], 0.0000)                 AS confidenceScore,
        ISNULL([is_verified], 0)                           AS isVerified,

        -- Legal Contract Metadata
        ISNULL([contract_accepted], 0)                     AS contractAccepted,
        ISNULL([contract_pdf_blob_url], '')                AS contractPdfBlobUrl,
        ISNULL(CONVERT(VARCHAR(30), [contract_accepted_at], 126), '') AS contractAcceptedAt,

        -- Legal Pagaré Metadata
        ISNULL([pagare_accepted], 0)                       AS pagareAccepted,
        ISNULL([pagare_pdf_blob_url], '')                  AS pagarePdfBlobUrl,
        ISNULL(CONVERT(VARCHAR(30), [pagare_accepted_at], 126), '')   AS pagareAcceptedAt,
        ISNULL([has_physical_pagare], 0)                   AS hasPhysicalPagare,
        ISNULL(CONVERT(VARCHAR(30), [physical_pagare_verified_at], 126), '') AS physicalPagareVerifiedAt,

        -- Presence capture (video + GPS)
        ISNULL([presence_video_blob_url], '')              AS presenceVideoBlobUrl,
        [presence_latitude]                                AS presenceLatitude,
        [presence_longitude]                                AS presenceLongitude,
        [presence_location_accuracy_meters]                AS presenceLocationAccuracyMeters,
        ISNULL(CONVERT(VARCHAR(30), [presence_captured_at], 126), '') AS presenceCapturedAt,

        -- Signature match
        ISNULL([id_signature_crop_blob_url], '')            AS idSignatureCropBlobUrl,
        ISNULL([contract_signature_blob_url], '')           AS contractSignatureBlobUrl,
        [signature_match_score]                             AS signatureMatchScore,
        [signature_match_passed]                            AS signatureMatchPassed,
        ISNULL(CONVERT(VARCHAR(30), [signature_matched_at], 126), '') AS signatureMatchedAt,

        -- System Audit Columns
        ISNULL([is_active], 1)                             AS isActive,
        ISNULL([created_by], 1)                            AS createdBy,
        ISNULL(CONVERT(VARCHAR(30), [created_At], 126), '') AS createdAt,
        [updated_by]                                       AS updatedBy,
        ISNULL(CONVERT(VARCHAR(30), [updated_at], 126), '') AS updatedAt
    FROM dbo.ClientFaceRecognitions
    WHERE companyId = @companyId
      AND [is_active] = 1 -- Ensures soft-deleted rows stay out of client listings
    FOR JSON AUTO, ROOT('clientFaceRecognitions');
END;
GO

-- NOTE: sp_clientFaceRecognitions_one has a pre-existing bug in its ID-
-- extraction logic (unrelated to this migration, confirmed unreachable by
-- any real caller — even its own documented example payload in
-- docs_description/clientFaceRecognitions_one.txt hits the same parse
-- error). Not fixed here since it's out of scope for this change and has
-- no current callers; flagging for whoever picks it up next.
CREATE OR ALTER PROC [dbo].[sp_clientFaceRecognitions_one] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @clientFaceRecognitionId INT;
    SET @clientFaceRecognitionId = CAST(
        (SELECT TOP 1 JSON_VALUE(value, '$.clientFaceRecognitions')
         FROM OPENJSON(@pjsonfile)) AS INT
    );

    SELECT
        [clientFaceRecognitionId],
        ISNULL([companyId], 0)                             AS companyId,
        ISNULL([clientId], 0)                              AS clientId,
        ISNULL([document_type], '')                        AS documentType,
        ISNULL([id_front_image_blob_url], '')              AS idFrontImageBlobUrl,
        ISNULL([id_back_image_blob_url], '')               AS idBackImageBlobUrl,
        [azure_session_id]                                 AS azureSessionId,
        ISNULL([client_selfie_blob_url], '')               AS clientSelfieBlobUrl,
        ISNULL([confidence_score], 0.0000)                 AS confidenceScore,
        ISNULL([is_verified], 0)                           AS isVerified,

        -- Legal Contract Metadata
        ISNULL([contract_accepted], 0)                     AS contractAccepted,
        ISNULL([contract_pdf_blob_url], '')                AS contractPdfBlobUrl,
        ISNULL(CONVERT(VARCHAR(30), [contract_accepted_at], 126), '') AS contractAcceptedAt,

        -- Legal Pagaré Metadata
        ISNULL([pagare_accepted], 0)                       AS pagareAccepted,
        ISNULL([pagare_pdf_blob_url], '')                  AS pagarePdfBlobUrl,
        ISNULL(CONVERT(VARCHAR(30), [pagare_accepted_at], 126), '')   AS pagareAcceptedAt,
        ISNULL([has_physical_pagare], 0)                   AS hasPhysicalPagare,
        ISNULL(CONVERT(VARCHAR(30), [physical_pagare_verified_at], 126), '') AS physicalPagareVerifiedAt,

        -- Presence capture (video + GPS)
        ISNULL([presence_video_blob_url], '')              AS presenceVideoBlobUrl,
        [presence_latitude]                                AS presenceLatitude,
        [presence_longitude]                                AS presenceLongitude,
        [presence_location_accuracy_meters]                AS presenceLocationAccuracyMeters,
        ISNULL(CONVERT(VARCHAR(30), [presence_captured_at], 126), '') AS presenceCapturedAt,

        -- Signature match
        ISNULL([id_signature_crop_blob_url], '')            AS idSignatureCropBlobUrl,
        ISNULL([contract_signature_blob_url], '')           AS contractSignatureBlobUrl,
        [signature_match_score]                             AS signatureMatchScore,
        [signature_match_passed]                            AS signatureMatchPassed,
        ISNULL(CONVERT(VARCHAR(30), [signature_matched_at], 126), '') AS signatureMatchedAt,

        -- System Audit Columns
        ISNULL([is_active], 1)                             AS isActive,
        ISNULL([created_by], 1)                            AS createdBy,
        ISNULL(CONVERT(VARCHAR(30), [created_At], 126), '') AS createdAt,
        [updated_by]                                       AS updatedBy,
        ISNULL(CONVERT(VARCHAR(30), [updated_at], 126), '') AS updatedAt
    FROM dbo.ClientFaceRecognitions
    WHERE clientFaceRecognitionId = @clientFaceRecognitionId
    FOR JSON AUTO, ROOT('clientFaceRecognitions');
END;
GO
