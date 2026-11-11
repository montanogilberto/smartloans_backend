-- =============================================================================
-- dbo.sp_demandSignals_one — one demand signal of a company (phone masked)
-- =============================================================================
-- { "demandSignals": [{ "companyId": int, "demandSignalId": int }] }
-- The company filter is mandatory: an id from another company returns nothing.
-- Returns {"result":[{"demandSignals":[ {...} ]}]} or {"error": "..."}.
-- =============================================================================
CREATE OR ALTER PROC [dbo].[sp_demandSignals_one]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT, @id INT;
        SELECT TOP 1
            @companyId = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            @id        = TRY_CONVERT(INT, JSON_VALUE(value, '$.demandSignalId'))
        FROM OPENJSON(@pjsonfile, '$.demandSignals');

        IF @companyId IS NULL OR @id IS NULL
        BEGIN
            SELECT '{"error":"companyId and demandSignalId are required"}' AS jsonResult;
            RETURN;
        END;

        DECLARE @rowJson NVARCHAR(MAX) = (
            SELECT
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
            WHERE ds.demandSignalId = @id AND ds.companyId = @companyId
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"demandSignals":' + ISNULL(@rowJson, '[]') + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '''') + '"}') AS jsonResult;
    END CATCH
END;
GO
