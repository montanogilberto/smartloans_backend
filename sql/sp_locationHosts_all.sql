-- =============================================================================
-- dbo.sp_locationHosts_all — one company's host candidates, newest first, max 500
-- =============================================================================
-- Filters: status, zoneName, startDate/endDate (Hermosillo days, fixed UTC-7,
-- default last 90 days). Returns the contact phone: the route only serves
-- admin/manager sessions of the company (they must call the business back).
-- { "locationHosts": [{ "companyId": int, "status"?, "zoneName"?, "startDate"?, "endDate"? }] }
-- Returns {"result":[{"locationHosts":[...]}]} or {"error": "..."}.
-- =============================================================================
CREATE OR ALTER PROC [dbo].[sp_locationHosts_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT, @status NVARCHAR(20), @zoneName NVARCHAR(120), @startDate DATE, @endDate DATE;
        SELECT TOP 1
            @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            @status    = NULLIF(JSON_VALUE(value, '$.status'), ''),
            @zoneName  = NULLIF(JSON_VALUE(value, '$.zoneName'), ''),
            @startDate = TRY_CONVERT(DATE, JSON_VALUE(value, '$.startDate')),
            @endDate   = TRY_CONVERT(DATE, JSON_VALUE(value, '$.endDate'))
        FROM OPENJSON(@pjsonfile, '$.locationHosts');

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END;

        DECLARE @todayLocal DATE = CAST(DATEADD(HOUR, -7, SYSUTCDATETIME()) AS DATE);
        SET @endDate = ISNULL(@endDate, @todayLocal);
        SET @startDate = ISNULL(@startDate, DATEADD(DAY, -89, @endDate));
        DECLARE @fromUtc DATETIME2 = DATEADD(HOUR, 7, CAST(@startDate AS DATETIME2));
        DECLARE @toUtc DATETIME2 = DATEADD(HOUR, 7, CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2));

        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT TOP 500
                lh.locationHostId, lh.origin, lh.businessName, lh.businessType, lh.contactName, lh.contactRole,
                lh.contactPhone, lh.zoneText, lh.addressText, lh.zoneName, lh.zoneLat, lh.zoneLng,
                lh.openingHours, lh.opensWeekends, lh.spaceType, lh.dailyVisitors, lh.hasParking,
                lh.contactOptIn, lh.status, lh.staffNotes, mla.sourceId, mla.headline,
                CONVERT(NVARCHAR(19), lh.created_at, 126) AS created_at,
                CONVERT(NVARCHAR(19), lh.updated_at, 126) AS updated_at
            FROM dbo.locationHosts AS lh
            LEFT JOIN dbo.marketingLeadAttributions AS mla
                   ON mla.marketingLeadAttributionId = lh.marketingLeadAttributionId
                  AND mla.companyId = lh.companyId
            WHERE lh.companyId = @companyId
              AND lh.created_at >= @fromUtc AND lh.created_at < @toUtc
              AND (@status IS NULL OR lh.status = @status)
              AND (@zoneName IS NULL OR lh.zoneName = @zoneName)
            ORDER BY lh.created_at DESC
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"locationHosts":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '''') + '"}') AS jsonResult;
    END CATCH
END;
GO
