-- ============================================================================
-- KYC — third signed document: "Constancia de resguardo del pagaré físico".
--
-- The Contrato step now produces three PDFs: contrato de crédito
-- (contract_pdf_blob_url), pagaré (pagare_pdf_blob_url) and this constancia,
-- which records that the borrower acknowledged the physical pagaré is held in
-- custody (has_physical_pagare). Its Azure blob URL is stored here.
--
-- Same approach as 2026-11-19_kyc_ine_cic_ocr.sql: sp_clientFaceRecognitions is
-- NOT changed (it only exists in the live DB and drifts from the repo snapshot).
-- A small dedicated SP writes / lists this one column instead;
-- modules/clientFaceRecognitions.py calls it after the normal save and merges
-- it into the all/one reads.
--
-- BEFORE APPLYING (the local .env may point at the PRODUCTION database):
--   1. Check the backend startup banner: [appEnv][startup] APP_ENV=... DB=...
--   2. Apply in DEV first, then QA, then PROD (development -> qa -> main).
-- Idempotent (re-runnable).
-- ============================================================================

IF COL_LENGTH('dbo.clientFaceRecognitions', 'resguardo_pdf_blob_url') IS NULL
    ALTER TABLE dbo.clientFaceRecognitions ADD resguardo_pdf_blob_url NVARCHAR(2048) NULL;
GO

-- action 'set'  : { "clientFaceRecognitions": [{ "action": "set", "companyId": int, "clientId": int,
--                   "clientFaceRecognitionId": int, "resguardoPdfBlobUrl": str }] }
--                 Only the row of that company + client is touched.
-- action 'list' : { "clientFaceRecognitions": [{ "action": "list", "companyId": int, "clientId"?: int }] }
--                 -> { "resguardos": [{ "clientFaceRecognitionId": int, "resguardoPdfBlobUrl": str }] }
--                 (rows with a stored URL only; all clients of the company when clientId is absent)
CREATE OR ALTER PROCEDURE dbo.sp_clientFaceRecognitions_resguardo
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action    NVARCHAR(10)   = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].action');
        DECLARE @companyId INT            = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].companyId');
        DECLARE @clientId  INT            = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].clientId');
        DECLARE @id        INT            = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].clientFaceRecognitionId');
        DECLARE @url       NVARCHAR(2048) = JSON_VALUE(@pjsonfile, '$.clientFaceRecognitions[0].resguardoPdfBlobUrl');

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId es requerido."}' AS [jsonResult];
            RETURN;
        END

        IF @action = 'set'
        BEGIN
            IF @clientId IS NULL OR @id IS NULL OR NULLIF(@url, '') IS NULL
            BEGIN
                SELECT '{"error":"clientId, clientFaceRecognitionId y resguardoPdfBlobUrl son requeridos."}' AS [jsonResult];
                RETURN;
            END

            UPDATE dbo.clientFaceRecognitions
               SET resguardo_pdf_blob_url = @url,
                   updated_at = GETUTCDATE()
             WHERE clientFaceRecognitionId = @id AND companyId = @companyId AND clientId = @clientId;

            SELECT '{"updated":' + CAST(@@ROWCOUNT AS NVARCHAR) + '}' AS [jsonResult];
        END
        ELSE IF @action = 'list'
        BEGIN
            SELECT ISNULL((
                SELECT clientFaceRecognitionId,
                       resguardo_pdf_blob_url AS resguardoPdfBlobUrl
                FROM dbo.clientFaceRecognitions
                WHERE companyId = @companyId
                  AND (@clientId IS NULL OR clientId = @clientId)
                  AND resguardo_pdf_blob_url IS NOT NULL
                FOR JSON PATH, ROOT('resguardos')
            ), '{"resguardos":[]}') AS [jsonResult];
        END
        ELSE
            SELECT '{"error":"action debe ser set o list."}' AS [jsonResult];
    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult];
    END CATCH
END
GO
