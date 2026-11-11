-- =============================================================================
-- dbo.sp_demandSignals_zoneSummary — demand map: people per zone and concept
-- =============================================================================
-- Same filters as sp_demandSignals_all (minus intentLevel/sourceId). Counts
-- DISTINCT phones. A zone+concept with fewer than 3 people is folded into
-- 'otras zonas' (no coordinates) so nobody can be identified. Signals whose zone
-- could not be located yet (preferredZoneName NULL) go to 'sin ubicar'.
-- { "demandSignals": [{ "companyId": int, "startDate"?, "endDate"?, "concept"?, "origin"? }] }
-- Returns {"result":[{"zones":[{zoneName, lat, lng, concept, people, alta, media,
--   baja, pctRecurring, topPreferredTime, newProspects, existingClients, optIns}]}]}
-- =============================================================================
CREATE OR ALTER PROC [dbo].[sp_demandSignals_zoneSummary]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT, @startDate DATE, @endDate DATE, @concept NVARCHAR(30), @origin NVARCHAR(20);
        SELECT TOP 1
            @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            @startDate = TRY_CONVERT(DATE, JSON_VALUE(value, '$.startDate')),
            @endDate   = TRY_CONVERT(DATE, JSON_VALUE(value, '$.endDate')),
            @concept   = NULLIF(JSON_VALUE(value, '$.concept'), ''),
            @origin    = NULLIF(JSON_VALUE(value, '$.origin'), '')
        FROM OPENJSON(@pjsonfile, '$.demandSignals');

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END;

        DECLARE @todayLocal DATE = CAST(DATEADD(HOUR, -7, SYSUTCDATETIME()) AS DATE);
        SET @endDate = ISNULL(@endDate, @todayLocal);
        SET @startDate = ISNULL(@startDate, DATEADD(DAY, -29, @endDate));
        DECLARE @fromUtc DATETIME2 = DATEADD(HOUR, 7, CAST(@startDate AS DATETIME2));
        DECLARE @toUtc DATETIME2 = DATEADD(HOUR, 7, CAST(DATEADD(DAY, 1, @endDate) AS DATETIME2));

        DECLARE @zonesJson NVARCHAR(MAX);

        WITH filtered AS (
            SELECT ds.customerPhone, ds.concept, ds.intentLevel, ds.frequency, ds.preferredTime,
                   ds.clientId, ds.notifyOptIn, ds.preferredZoneLat, ds.preferredZoneLng,
                   ISNULL(ds.preferredZoneName, N'sin ubicar') AS zoneKey
            FROM dbo.demandSignals AS ds
            WHERE ds.companyId = @companyId
              AND ds.created_at >= @fromUtc AND ds.created_at < @toUtc
              AND (@concept IS NULL OR ds.concept = @concept)
              AND (@origin IS NULL OR ds.origin = @origin)
        ),
        zoneSize AS (
            SELECT concept, zoneKey, COUNT(DISTINCT customerPhone) AS people,
                   AVG(preferredZoneLat) AS lat, AVG(preferredZoneLng) AS lng
            FROM filtered GROUP BY concept, zoneKey
        ),
        folded AS (
            SELECT f.*,
                   CASE WHEN z.people < 3 THEN N'otras zonas' ELSE f.zoneKey END AS zoneName,
                   CASE WHEN z.people < 3 OR f.zoneKey = N'sin ubicar' THEN NULL ELSE z.lat END AS zLat,
                   CASE WHEN z.people < 3 OR f.zoneKey = N'sin ubicar' THEN NULL ELSE z.lng END AS zLng
            FROM filtered AS f
            JOIN zoneSize AS z ON z.concept = f.concept AND z.zoneKey = f.zoneKey
        ),
        topTime AS (
            SELECT concept, zoneName, preferredTime,
                   ROW_NUMBER() OVER (PARTITION BY concept, zoneName
                                      ORDER BY COUNT(DISTINCT customerPhone) DESC, preferredTime) AS rn
            FROM folded WHERE preferredTime IS NOT NULL
            GROUP BY concept, zoneName, preferredTime
        )
        SELECT @zonesJson = (
            SELECT fo.zoneName,
                   MAX(fo.zLat) AS lat, MAX(fo.zLng) AS lng,
                   fo.concept,
                   COUNT(DISTINCT fo.customerPhone) AS people,
                   COUNT(DISTINCT CASE WHEN fo.intentLevel = 'alta'  THEN fo.customerPhone END) AS alta,
                   COUNT(DISTINCT CASE WHEN fo.intentLevel = 'media' THEN fo.customerPhone END) AS media,
                   COUNT(DISTINCT CASE WHEN fo.intentLevel = 'baja'  THEN fo.customerPhone END) AS baja,
                   CAST(100.0 * COUNT(DISTINCT CASE WHEN fo.frequency IN ('semanal', 'quincenal') THEN fo.customerPhone END)
                        / NULLIF(COUNT(DISTINCT fo.customerPhone), 0) AS DECIMAL(5,1)) AS pctRecurring,
                   MAX(tt.preferredTime) AS topPreferredTime,
                   COUNT(DISTINCT CASE WHEN fo.clientId IS NULL     THEN fo.customerPhone END) AS newProspects,
                   COUNT(DISTINCT CASE WHEN fo.clientId IS NOT NULL THEN fo.customerPhone END) AS existingClients,
                   COUNT(DISTINCT CASE WHEN fo.notifyOptIn = 1      THEN fo.customerPhone END) AS optIns
            FROM folded AS fo
            LEFT JOIN topTime AS tt ON tt.concept = fo.concept AND tt.zoneName = fo.zoneName AND tt.rn = 1
            GROUP BY fo.concept, fo.zoneName
            ORDER BY COUNT(DISTINCT fo.customerPhone) DESC
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"zones":' + ISNULL(@zonesJson, '[]') + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '''') + '"}') AS jsonResult;
    END CATCH
END;
GO
