-- =============================================================================
-- dbo.sp_demandSignals — upsert of one demand signal (companyId, customerPhone, concept)
-- =============================================================================
-- Called only by modules/demandSignals.record_demand_signal (WhatsApp webhook path).
-- When no marketingLeadAttributionId is sent, the latest ad attribution for this
-- phone and channel is linked (origin becomes 'anuncio').
-- A later call overwrites only the fields it sends (NULL = keep), so the agent can
-- record progressively. intentLevel is computed here; any value sent is ignored.
--   alta  = wouldUse 'si' AND frequency IN (semanal, quincenal) AND notifyOptIn = 1
--   media = wouldUse IN (si, tal_vez) otherwise
--   baja  = wouldUse 'no' or unknown
-- There is no delete action. @pjsonfile:
-- { "demandSignals": [{ "companyId", "channelId", "customerPhone", "concept",
--   "origin"?, "clientId"?, "marketingLeadAttributionId"?, "residenceZoneText"?,
--   "workZoneText"?, "preferredZoneText"?, "preferredZoneName"?, "preferredZoneLat"?,
--   "preferredZoneLng"?, "frequency"?, "preferredTime"?, "currentSolution"?,
--   "painPoint"?, "wouldUse"?, "notifyOptIn"? }] }
-- Returns {"result":[{"demandSignalId", "intentLevel"}]} or {"error": "..."}.
-- =============================================================================
CREATE OR ALTER PROC [dbo].[sp_demandSignals]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT, @channelId INT, @customerPhone NVARCHAR(20), @concept NVARCHAR(30),
                @origin NVARCHAR(20), @clientId INT, @attributionId INT,
                @residence NVARCHAR(120), @work NVARCHAR(120), @zoneText NVARCHAR(120),
                @zoneName NVARCHAR(120), @lat DECIMAL(9,6), @lng DECIMAL(9,6),
                @frequency NVARCHAR(20), @preferredTime NVARCHAR(20), @currentSolution NVARCHAR(20),
                @painPoint NVARCHAR(200), @wouldUse NVARCHAR(10), @optIn BIT;

        SELECT TOP 1
            @companyId       = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            @channelId       = TRY_CONVERT(INT, JSON_VALUE(value, '$.channelId')),
            @customerPhone   = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.customerPhone'))), ''),
            @concept         = NULLIF(JSON_VALUE(value, '$.concept'), ''),
            @origin          = NULLIF(JSON_VALUE(value, '$.origin'), ''),
            @clientId        = TRY_CONVERT(INT, JSON_VALUE(value, '$.clientId')),
            @attributionId   = TRY_CONVERT(INT, JSON_VALUE(value, '$.marketingLeadAttributionId')),
            @residence       = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.residenceZoneText'))), ''),
            @work            = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.workZoneText'))), ''),
            @zoneText        = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.preferredZoneText'))), ''),
            @zoneName        = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.preferredZoneName'))), ''),
            @lat             = TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.preferredZoneLat')),
            @lng             = TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.preferredZoneLng')),
            @frequency       = NULLIF(JSON_VALUE(value, '$.frequency'), ''),
            @preferredTime   = NULLIF(JSON_VALUE(value, '$.preferredTime'), ''),
            @currentSolution = NULLIF(JSON_VALUE(value, '$.currentSolution'), ''),
            @painPoint       = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.painPoint'))), ''),
            @wouldUse        = NULLIF(JSON_VALUE(value, '$.wouldUse'), ''),
            @optIn           = TRY_CONVERT(BIT, JSON_VALUE(value, '$.notifyOptIn'))
        FROM OPENJSON(@pjsonfile, '$.demandSignals');

        IF @companyId IS NULL OR @channelId IS NULL OR @customerPhone IS NULL OR @concept IS NULL
        BEGIN
            SELECT '{"error":"companyId, channelId, customerPhone and concept are required"}' AS jsonResult;
            RETURN;
        END;

        -- Tenancy: the channel must belong to the company.
        IF NOT EXISTS (SELECT 1 FROM dbo.whatsappChannels WHERE channelId = @channelId AND companyId = @companyId)
        BEGIN
            SELECT '{"error":"channel does not belong to company"}' AS jsonResult;
            RETURN;
        END;

        -- The attribution and the client must belong to the company too (else dropped).
        IF @attributionId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM dbo.marketingLeadAttributions
            WHERE marketingLeadAttributionId = @attributionId AND companyId = @companyId)
            SET @attributionId = NULL;
        IF @clientId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM dbo.clients WHERE clientId = @clientId AND companyId = @companyId)
            SET @clientId = NULL;

        -- The ad that brought this person: the latest attribution for this phone
        -- on this channel (written by the webhook on the first message after the click).
        IF @attributionId IS NULL
            SELECT TOP 1 @attributionId = marketingLeadAttributionId
            FROM dbo.marketingLeadAttributions
            WHERE companyId = @companyId AND channelId = @channelId AND customerPhone = @customerPhone
            ORDER BY referredAt DESC, marketingLeadAttributionId DESC;

        DECLARE @id INT, @intent NVARCHAR(10);

        BEGIN TRANSACTION;

        SELECT @id = demandSignalId
        FROM dbo.demandSignals WITH (UPDLOCK, HOLDLOCK)
        WHERE companyId = @companyId AND customerPhone = @customerPhone AND concept = @concept;

        IF @id IS NULL
        BEGIN
            IF @zoneText IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT '{"error":"preferredZoneText is required for a new signal"}' AS jsonResult;
                RETURN;
            END;
            SET @intent = CASE
                WHEN @wouldUse = 'si' AND @frequency IN ('semanal', 'quincenal') AND ISNULL(@optIn, 0) = 1 THEN 'alta'
                WHEN @wouldUse IN ('si', 'tal_vez') THEN 'media'
                ELSE 'baja' END;
            INSERT INTO dbo.demandSignals (
                companyId, channelId, customerPhone, clientId, marketingLeadAttributionId, concept, origin,
                residenceZoneText, workZoneText, preferredZoneText, preferredZoneName, preferredZoneLat, preferredZoneLng,
                frequency, preferredTime, currentSolution, painPoint, wouldUse, notifyOptIn, optInAt, intentLevel)
            VALUES (
                @companyId, @channelId, @customerPhone, @clientId, @attributionId, @concept,
                COALESCE(@origin, CASE WHEN @attributionId IS NOT NULL THEN 'anuncio' ELSE 'organico' END),
                @residence, @work, @zoneText, @zoneName, @lat, @lng,
                @frequency, @preferredTime, @currentSolution, @painPoint, @wouldUse, ISNULL(@optIn, 0),
                CASE WHEN @optIn = 1 THEN SYSUTCDATETIME() END, @intent);
            SET @id = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE dbo.demandSignals SET
                channelId                  = @channelId,
                clientId                   = COALESCE(@clientId, clientId),
                marketingLeadAttributionId = COALESCE(@attributionId, marketingLeadAttributionId),
                origin                     = COALESCE(@origin, CASE WHEN @attributionId IS NOT NULL THEN 'anuncio' END, origin),
                residenceZoneText          = COALESCE(@residence, residenceZoneText),
                workZoneText               = COALESCE(@work, workZoneText),
                preferredZoneText          = COALESCE(@zoneText, preferredZoneText),
                preferredZoneName          = COALESCE(@zoneName, preferredZoneName),
                preferredZoneLat           = COALESCE(@lat, preferredZoneLat),
                preferredZoneLng           = COALESCE(@lng, preferredZoneLng),
                frequency                  = COALESCE(@frequency, frequency),
                preferredTime              = COALESCE(@preferredTime, preferredTime),
                currentSolution            = COALESCE(@currentSolution, currentSolution),
                painPoint                  = COALESCE(@painPoint, painPoint),
                wouldUse                   = COALESCE(@wouldUse, wouldUse),
                optInAt                    = CASE WHEN notifyOptIn = 0 AND @optIn = 1 THEN SYSUTCDATETIME() ELSE optInAt END,
                notifyOptIn                = COALESCE(@optIn, notifyOptIn),
                updated_at                 = SYSUTCDATETIME()
            WHERE demandSignalId = @id;

            UPDATE dbo.demandSignals SET intentLevel = CASE
                WHEN wouldUse = 'si' AND frequency IN ('semanal', 'quincenal') AND notifyOptIn = 1 THEN 'alta'
                WHEN wouldUse IN ('si', 'tal_vez') THEN 'media'
                ELSE 'baja' END
            WHERE demandSignalId = @id;
        END;

        COMMIT TRANSACTION;

        SELECT @intent = intentLevel FROM dbo.demandSignals WHERE demandSignalId = @id;
        SELECT ('{"result":[{"demandSignalId":' + CAST(@id AS NVARCHAR(12))
                + ',"intentLevel":"' + @intent + '"}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '''') + '"}') AS jsonResult;
    END CATCH
END;
GO
