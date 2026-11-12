-- =============================================================================
-- dbo.sp_locationHosts — upsert of a host candidate (companyId, contactPhone, businessName)
-- =============================================================================
-- Called only by modules/locationHosts.record_location_host (WhatsApp webhook path).
-- A later call overwrites only the fields it sends (NULL = keep). It never changes
-- status or staffNotes (staff use sp_locationHosts_status); new rows start 'nuevo'.
-- When no marketingLeadAttributionId is sent, the latest ad attribution for this
-- phone and channel is linked (origin becomes 'anuncio'). No delete.
-- { "locationHosts": [{ "companyId", "channelId", "contactPhone", "businessName",
--   "zoneText"?, "origin"?, "marketingLeadAttributionId"?, "businessType"?,
--   "contactName"?, "contactRole"?, "addressText"?, "zoneName"?, "zoneLat"?,
--   "zoneLng"?, "openingHours"?, "opensWeekends"?, "spaceType"?, "dailyVisitors"?,
--   "hasParking"?, "contactOptIn"? }] }
-- The business is matched ignoring case, accents and extra spaces ("Farmacia
-- Gómez" = "farmacia  gomez"), so one business is one row; the first spelling stays.
-- Returns {"result":[{"locationHostId", "status", "newOptIn"}]} or {"error": "..."}.
-- newOptIn is true only on the call that turned contactOptIn on, so the caller
-- alerts the team once.
-- =============================================================================
CREATE OR ALTER PROC [dbo].[sp_locationHosts]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @companyId INT, @channelId INT, @phone NVARCHAR(20), @businessName NVARCHAR(120),
                @zoneText NVARCHAR(120), @origin NVARCHAR(20), @attributionId INT,
                @businessType NVARCHAR(20), @contactName NVARCHAR(120), @contactRole NVARCHAR(20),
                @addressText NVARCHAR(200), @zoneName NVARCHAR(120), @lat DECIMAL(9,6), @lng DECIMAL(9,6),
                @openingHours NVARCHAR(120), @opensWeekends BIT, @spaceType NVARCHAR(20),
                @dailyVisitors NVARCHAR(20), @hasParking BIT, @optIn BIT;

        SELECT TOP 1
            @companyId     = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
            @channelId     = TRY_CONVERT(INT, JSON_VALUE(value, '$.channelId')),
            @phone         = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.contactPhone'))), ''),
            @businessName  = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.businessName'))), ''),
            @zoneText      = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.zoneText'))), ''),
            @origin        = NULLIF(JSON_VALUE(value, '$.origin'), ''),
            @attributionId = TRY_CONVERT(INT, JSON_VALUE(value, '$.marketingLeadAttributionId')),
            @businessType  = NULLIF(JSON_VALUE(value, '$.businessType'), ''),
            @contactName   = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.contactName'))), ''),
            @contactRole   = NULLIF(JSON_VALUE(value, '$.contactRole'), ''),
            @addressText   = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.addressText'))), ''),
            @zoneName      = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.zoneName'))), ''),
            @lat           = TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.zoneLat')),
            @lng           = TRY_CONVERT(DECIMAL(9,6), JSON_VALUE(value, '$.zoneLng')),
            @openingHours  = NULLIF(LTRIM(RTRIM(JSON_VALUE(value, '$.openingHours'))), ''),
            @opensWeekends = TRY_CONVERT(BIT, JSON_VALUE(value, '$.opensWeekends')),
            @spaceType     = NULLIF(JSON_VALUE(value, '$.spaceType'), ''),
            @dailyVisitors = NULLIF(JSON_VALUE(value, '$.dailyVisitors'), ''),
            @hasParking    = TRY_CONVERT(BIT, JSON_VALUE(value, '$.hasParking')),
            @optIn         = TRY_CONVERT(BIT, JSON_VALUE(value, '$.contactOptIn'))
        FROM OPENJSON(@pjsonfile, '$.locationHosts');

        IF @companyId IS NULL OR @channelId IS NULL OR @phone IS NULL OR @businessName IS NULL
        BEGIN
            SELECT '{"error":"companyId, channelId, contactPhone and businessName are required"}' AS jsonResult;
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.whatsappChannels WHERE channelId = @channelId AND companyId = @companyId)
        BEGIN
            SELECT '{"error":"channel does not belong to company"}' AS jsonResult;
            RETURN;
        END;

        IF @attributionId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM dbo.marketingLeadAttributions
            WHERE marketingLeadAttributionId = @attributionId AND companyId = @companyId)
            SET @attributionId = NULL;
        IF @attributionId IS NULL
            SELECT TOP 1 @attributionId = marketingLeadAttributionId
            FROM dbo.marketingLeadAttributions
            WHERE companyId = @companyId AND channelId = @channelId AND customerPhone = @phone
            ORDER BY referredAt DESC, marketingLeadAttributionId DESC;

        WHILE CHARINDEX('  ', @businessName) > 0
            SET @businessName = REPLACE(@businessName, '  ', ' ');

        DECLARE @id INT, @wasOptIn BIT, @newOptIn BIT = 0;
        BEGIN TRANSACTION;

        SELECT @id = locationHostId, @wasOptIn = contactOptIn
        FROM dbo.locationHosts WITH (UPDLOCK, HOLDLOCK)
        WHERE companyId = @companyId AND contactPhone = @phone
          AND businessName COLLATE Latin1_General_CI_AI = @businessName COLLATE Latin1_General_CI_AI;

        IF @id IS NULL
        BEGIN
            IF @zoneText IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT '{"error":"zoneText is required for a new host"}' AS jsonResult;
                RETURN;
            END;
            INSERT INTO dbo.locationHosts (
                companyId, channelId, contactPhone, marketingLeadAttributionId, origin, businessName,
                businessType, contactName, contactRole, zoneText, addressText, zoneName, zoneLat, zoneLng,
                openingHours, opensWeekends, spaceType, dailyVisitors, hasParking, contactOptIn, optInAt)
            VALUES (
                @companyId, @channelId, @phone, @attributionId,
                COALESCE(@origin, CASE WHEN @attributionId IS NOT NULL THEN 'anuncio' ELSE 'organico' END),
                @businessName, @businessType, @contactName, @contactRole, @zoneText, @addressText,
                @zoneName, @lat, @lng, @openingHours, @opensWeekends, @spaceType, @dailyVisitors,
                @hasParking, ISNULL(@optIn, 0), CASE WHEN @optIn = 1 THEN SYSUTCDATETIME() END);
            SET @id = SCOPE_IDENTITY();
            IF @optIn = 1 SET @newOptIn = 1;
        END
        ELSE
        BEGIN
            IF @optIn = 1 AND ISNULL(@wasOptIn, 0) = 0 SET @newOptIn = 1;
            UPDATE dbo.locationHosts SET
                channelId                  = @channelId,
                marketingLeadAttributionId = COALESCE(@attributionId, marketingLeadAttributionId),
                origin                     = COALESCE(@origin, CASE WHEN @attributionId IS NOT NULL THEN 'anuncio' END, origin),
                businessType               = COALESCE(@businessType, businessType),
                contactName                = COALESCE(@contactName, contactName),
                contactRole                = COALESCE(@contactRole, contactRole),
                zoneText                   = COALESCE(@zoneText, zoneText),
                addressText                = COALESCE(@addressText, addressText),
                zoneName                   = COALESCE(@zoneName, zoneName),
                zoneLat                    = COALESCE(@lat, zoneLat),
                zoneLng                    = COALESCE(@lng, zoneLng),
                openingHours               = COALESCE(@openingHours, openingHours),
                opensWeekends              = COALESCE(@opensWeekends, opensWeekends),
                spaceType                  = COALESCE(@spaceType, spaceType),
                dailyVisitors              = COALESCE(@dailyVisitors, dailyVisitors),
                hasParking                 = COALESCE(@hasParking, hasParking),
                optInAt                    = CASE WHEN contactOptIn = 0 AND @optIn = 1 THEN SYSUTCDATETIME() ELSE optInAt END,
                contactOptIn               = COALESCE(@optIn, contactOptIn),
                updated_at                 = SYSUTCDATETIME()
            WHERE locationHostId = @id;
        END;

        COMMIT TRANSACTION;

        DECLARE @status NVARCHAR(20) = (SELECT status FROM dbo.locationHosts WHERE locationHostId = @id);
        SELECT ('{"result":[{"locationHostId":' + CAST(@id AS NVARCHAR(12))
                + ',"status":"' + @status + '","newOptIn":'
                + CASE WHEN @newOptIn = 1 THEN 'true' ELSE 'false' END + '}]}') AS jsonResult;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT ('{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '''') + '"}') AS jsonResult;
    END CATCH
END;
GO
