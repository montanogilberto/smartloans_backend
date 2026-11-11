-- =============================================================================
-- dbo.sp_demandSignals_all — one company's demand signals, newest first, max 500
-- =============================================================================
-- Filters (all optional but companyId): startDate/endDate (Hermosillo days, fixed
-- UTC-7, default last 30 days), concept, origin, intentLevel, sourceId (the Meta ad
-- id from marketingLeadAttributions). Phones go out masked: last 4 digits only.
-- { "demandSignals": [{ "companyId": int, "startDate"?, "endDate"?, "concept"?,
--   "origin"?, "intentLevel"?, "sourceId"? }] }
-- Returns {"result":[{"demandSignals":[...]}]} or {"error": "..."}.
-- =============================================================================
CREATE OR ALTER PROC [dbo].[sp_demandSignals_all]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT, @startDate DATE, @endDate DATE, @concept NVARCHAR(30),
                @origin NVARCHAR(20), @intentLevel NVARCHAR(10), @sourceId NVARCHAR(64);

        SELECT TOP 1
            @companyId   = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            @startDate   = TRY_CONVERT(DATE, JSON_VALUE(value, '$.startDate')),
            @endDate     = TRY_CONVERT(DATE, JSON_VALUE(value, '$.endDate')),
            @concept     = NULLIF(JSON_VALUE(value, '$.concept'), ''),
            @origin      = NULLIF(JSON_VALUE(value, '$.origin'), ''),
            @intentLevel = NULLIF(JSON_VALUE(value, '$.intentLevel'), ''),
            @sourceId    = NULLIF(JSON_VALUE(value, '$.sourceId'), '')
        FROM OPENJSON(@pjsonfile, '$.demandSignals');

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END;

        -- Hermosillo is fixed UTC-7: local midnight = 07:00 UTC.
        DECLARE @todayLocal DATE = CAST(DATEADD(HOUR, -7, SYSUTCDATETIME()) AS DATE);
        SET @endDate = ISNULL(@endDate, @todayLocal);
        SET @startDate = ISNULL(@startDate, DATEADD(DAY, -29, @endDate));
        DECLARE @fromUtc DATETIME2 = DATEADD(HOUR, 7, CAST(@startDate AS DATETIME2));
        DECLARE @toUtc DATETIME2 = DATEADD(HOUR, 7, CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2));

        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT TOP 500
                ds.demandSignalId, ds.channelId, ds.concept, ds.origin,
                ds.preferredZoneText, ds.preferredZoneName, ds.preferredZoneLat, ds.preferredZoneLng,
                ds.residenceZoneText, ds.workZoneText, ds.frequency, ds.preferredTime,
                ds.currentSolution, ds.painPoint, ds.wouldUse, ds.notifyOptIn, ds.intentLevel,
                CAST(CASE WHEN ds.clientId IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS isExistingClient,
                mla.sourceId, mla.headline,
                RIGHT(ds.customerPhone, 4) AS phoneLast4,
                CONVERT(NVARCHAR(19), ds.optInAt, 126)    AS optInAt,
                CONVERT(NVARCHAR(19), ds.created_at, 126) AS created_at,
                CONVERT(NVARCHAR(19), ds.updated_at, 126) AS updated_at
            FROM dbo.demandSignals AS ds
            LEFT JOIN dbo.marketingLeadAttributions AS mla
                   ON mla.marketingLeadAttributionId = ds.marketingLeadAttributionId
                  AND mla.companyId = ds.companyId
            WHERE ds.companyId = @companyId
              AND ds.created_at >= @fromUtc AND ds.created_at < @toUtc
              AND (@concept IS NULL OR ds.concept = @concept)
              AND (@origin IS NULL OR ds.origin = @origin)
              AND (@intentLevel IS NULL OR ds.intentLevel = @intentLevel)
              AND (@sourceId IS NULL OR mla.sourceId = @sourceId)
            ORDER BY ds.created_at DESC
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"demandSignals":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '''') + '"}') AS jsonResult;
    END CATCH
END;
GO
