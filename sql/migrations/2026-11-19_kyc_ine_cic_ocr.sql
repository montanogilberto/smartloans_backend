-- ============================================================================
-- RFC-015 step 1 — INE back-side identifiers on the KYC record
-- (POSVending docs/rfcs/RFC-015-kyc-ine-cic-ocr.md).
--
-- CIC (9 digits) and OCR (13 digits) come from the machine-readable zone on
-- the BACK of the INE; vigencia (4-digit year) from the FRONT. They are what an authorized INE Lista Nominal check
-- needs (RFC-015 step 2), so they are stored next to curp / clave_elector.
--
-- Deliberately NOT a change to sp_clientFaceRecognitions: that SP only exists
-- in the live database (the repo copy is the 2026-08-15 snapshot) and the live
-- schema drifts from the repo. A small dedicated SP writes these columns on
-- an existing row instead; modules/clientFaceRecognitions.py calls it right
-- after the normal save succeeds.
--
-- BEFORE APPLYING (the local .env may point at the PRODUCTION database):
--   1. Check the backend startup banner: [appEnv][startup] APP_ENV=... DB=...
--   2. Apply in DEV first, then QA, then PROD (development -> qa -> main).
-- Idempotent (re-runnable). Personal data: never log these values.
-- ============================================================================

IF COL_LENGTH('dbo.clientFaceRecognitions', 'cic') IS NULL
    ALTER TABLE dbo.clientFaceRecognitions ADD cic NVARCHAR(9) NULL;
GO

IF COL_LENGTH('dbo.clientFaceRecognitions', 'ocr') IS NULL
    ALTER TABLE dbo.clientFaceRecognitions ADD ocr NVARCHAR(13) NULL;
GO

-- Last year of the front's "VIGENCIA" (the INE is valid through Dec 31 of it).
IF COL_LENGTH('dbo.clientFaceRecognitions', 'vigencia') IS NULL
    ALTER TABLE dbo.clientFaceRecognitions ADD vigencia NVARCHAR(4) NULL;
GO

-- action 'set'  : { "clientFaceRecognitions": [{ "action": "set", "companyId": int,
--                   "clientId": int, "clientFaceRecognitionId": int, "cic"?: str, "ocr"?: str,
--                   "vigencia"?: str }] }
--                 Only the row of that company + client is touched. A key that is
--                 absent leaves the column as is; the backend sends only valid values.
-- action 'get'  : same keys without the values -> { "cic", "ocr", "vigencia" } (null when unknown)
CREATE OR ALTER PROCEDURE dbo.sp_clientFaceRecognitions_ineIds
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action  NVARCHAR(10) = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].action');
        DECLARE @companyId INT = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].companyId');
        DECLARE @clientId  INT = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].clientId');
        DECLARE @id        INT = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].clientFaceRecognitionId');
        DECLARE @cic NVARCHAR(9)  = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].cic');
        DECLARE @ocr NVARCHAR(13) = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].ocr');
        DECLARE @vigencia NVARCHAR(4) = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].vigencia');

        IF @companyId IS NULL OR @clientId IS NULL OR @id IS NULL
        BEGIN
            SELECT '{"error":"companyId, clientId y clientFaceRecognitionId son requeridos."}' AS [jsonResult];
            RETURN;
        END

        IF @action = 'set'
        BEGIN
            UPDATE dbo.clientFaceRecognitions
               SET cic = ISNULL(@cic, cic),
                   ocr = ISNULL(@ocr, ocr),
                   vigencia = ISNULL(@vigencia, vigencia),
                   updated_at = GETUTCDATE()
             WHERE clientFaceRecognitionId = @id AND companyId = @companyId AND clientId = @clientId;

            SELECT '{"updated":' + CAST(@@ROWCOUNT AS NVARCHAR) + '}' AS [jsonResult];
        END
        ELSE IF @action = 'get'
        BEGIN
            SELECT ISNULL((
                SELECT cic, ocr, vigencia
                FROM dbo.clientFaceRecognitions
                WHERE clientFaceRecognitionId = @id AND companyId = @companyId AND clientId = @clientId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
            ), '{}') AS [jsonResult];
        END
        ELSE
            SELECT '{"error":"action debe ser set o get."}' AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult];
    END CATCH
END
GO
