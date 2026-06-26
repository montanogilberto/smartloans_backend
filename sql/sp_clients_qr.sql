-- ============================================================
-- Run once on the production DB to add the qrBlobUrl column:
-- ALTER TABLE [dbo].[clients] ADD qrBlobUrl NVARCHAR(500) NULL;
-- ============================================================

-- ============================================================
-- sp_clients_qr  — update QR blob URL for a client
-- ============================================================
IF OBJECT_ID('dbo.sp_clients_qr', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_clients_qr;
GO

CREATE PROCEDURE [dbo].[sp_clients_qr]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @clientId  INT           = JSON_VALUE(@pjsonfile, '$.clients[0].clientId')
        DECLARE @companyId INT           = JSON_VALUE(@pjsonfile, '$.clients[0].companyId')
        DECLARE @qrBlobUrl NVARCHAR(500) = JSON_VALUE(@pjsonfile, '$.clients[0].qrBlobUrl')

        UPDATE [dbo].[clients]
        SET    qrBlobUrl  = @qrBlobUrl,
               updated_at = GETUTCDATE()
        WHERE  clientId   = @clientId
          AND  companyId  = @companyId

        SELECT '{"message":"qrBlobUrl updated","clientId":' + CAST(@clientId AS NVARCHAR) + '}' AS [jsonResult]
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(),'"','\"') + '"}') AS [jsonResult]
    END CATCH
END
GO
