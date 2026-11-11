-- =============================================================================
-- dbo.sp_locationHosts_status — staff moves a host candidate through the pipeline
-- =============================================================================
-- Changes ONLY status (and staffNotes when sent) of a row of that company.
-- { "locationHosts": [{ "companyId": int, "locationHostId": int, "status": string,
--   "staffNotes"?: string }] }
-- Returns {"result":[{"locationHostId", "status"}]} or {"error": "..."}.
-- =============================================================================
CREATE OR ALTER PROC [dbo].[sp_locationHosts_status]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT, @id INT, @status NVARCHAR(20), @notes NVARCHAR(500);
        SELECT TOP 1
            @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            @id        = TRY_CONVERT(INT, JSON_VALUE(value, '$.locationHostId')),
            @status    = NULLIF(JSON_VALUE(value, '$.status'), ''),
            @notes     = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.staffNotes'))), '')
        FROM OPENJSON(@pjsonfile, '$.locationHosts');

        IF @companyId IS NULL OR @id IS NULL OR @status IS NULL
        BEGIN
            SELECT '{"error":"companyId, locationHostId and status are required"}' AS jsonResult;
            RETURN;
        END;

        UPDATE dbo.locationHosts
        SET status = @status, staffNotes = COALESCE(@notes, staffNotes), updated_at = SYSUTCDATETIME()
        WHERE locationHostId = @id AND companyId = @companyId;

        IF @@ROWCOUNT = 0
        BEGIN
            SELECT '{"error":"host not found in company"}' AS jsonResult;
            RETURN;
        END;

        SELECT ('{"result":[{"locationHostId":' + CAST(@id AS NVARCHAR(12))
                + ',"status":"' + @status + '"}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '''') + '"}') AS jsonResult;
    END CATCH
END;
GO
