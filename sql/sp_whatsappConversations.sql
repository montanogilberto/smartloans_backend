-- ============================================================
-- Per-chat state of the WhatsApp reservations bot, keyed by
-- (channelId, customerPhone). Expiry is evaluated here with the DB clock,
-- so every App Service instance sees the same answer.
--   0  get state            1  set pending proposal (ttlSeconds)
--   2  clear pending        3  pause bot for staff (pauseSeconds; clears pending)
--   4  set last booking
-- Every action returns the current state:
--   {"result":[{"pending": {...}|null, "staffPaused": bool, "lastBooked": {...}|null}]}
-- Table: sql/migrations/2026-09-28_whatsapp_channels.sql
-- ============================================================

IF OBJECT_ID('dbo.sp_whatsappConversations', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_whatsappConversations;
GO
CREATE PROCEDURE [dbo].[sp_whatsappConversations]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action     INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.whatsappConversations[0].action'));
        DECLARE @channelId  INT           = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.whatsappConversations[0].channelId'));
        DECLARE @phone      NVARCHAR(20)  =                  JSON_VALUE(@pjsonfile, '$.whatsappConversations[0].customerPhone');
        DECLARE @seconds    INT           = TRY_CONVERT(INT, COALESCE(
                                                JSON_VALUE(@pjsonfile, '$.whatsappConversations[0].ttlSeconds'),
                                                JSON_VALUE(@pjsonfile, '$.whatsappConversations[0].pauseSeconds')));
        DECLARE @pending    NVARCHAR(MAX) = JSON_QUERY(@pjsonfile, '$.whatsappConversations[0].pending');
        DECLARE @lastBooked NVARCHAR(MAX) = JSON_QUERY(@pjsonfile, '$.whatsappConversations[0].lastBooked');
        DECLARE @now        DATETIME2     = GETUTCDATE();

        IF @channelId IS NULL OR @phone IS NULL
        BEGIN
            SELECT '{"error":"channelId and customerPhone are required"}' AS jsonResult;
            RETURN;
        END

        IF @action IN (1, 2, 3, 4)
           AND NOT EXISTS (SELECT 1 FROM [dbo].[whatsappConversations]
                           WHERE channelId = @channelId AND customerPhone = @phone)
            INSERT INTO [dbo].[whatsappConversations] (channelId, customerPhone)
            VALUES (@channelId, @phone);

        IF @action = 1
        BEGIN
            IF @pending IS NULL OR @seconds IS NULL
            BEGIN
                SELECT '{"error":"pending (object) and ttlSeconds are required"}' AS jsonResult;
                RETURN;
            END
            UPDATE [dbo].[whatsappConversations]
            SET pendingJson = @pending, pendingExpiresAt = DATEADD(SECOND, @seconds, @now), updatedAt = @now
            WHERE channelId = @channelId AND customerPhone = @phone;
        END
        ELSE IF @action = 2
            UPDATE [dbo].[whatsappConversations]
            SET pendingJson = NULL, pendingExpiresAt = NULL, updatedAt = @now
            WHERE channelId = @channelId AND customerPhone = @phone;
        ELSE IF @action = 3
        BEGIN
            IF @seconds IS NULL
            BEGIN
                SELECT '{"error":"pauseSeconds is required"}' AS jsonResult;
                RETURN;
            END
            UPDATE [dbo].[whatsappConversations]
            SET staffPausedUntil = DATEADD(SECOND, @seconds, @now),
                pendingJson = NULL, pendingExpiresAt = NULL, updatedAt = @now
            WHERE channelId = @channelId AND customerPhone = @phone;
        END
        ELSE IF @action = 4
            UPDATE [dbo].[whatsappConversations]
            SET lastBookedJson = @lastBooked, updatedAt = @now
            WHERE channelId = @channelId AND customerPhone = @phone;

        DECLARE @pendingOut NVARCHAR(MAX) = NULL, @lastOut NVARCHAR(MAX) = NULL, @paused BIT = 0;
        SELECT @pendingOut = CASE WHEN pendingExpiresAt > @now THEN pendingJson END,
               @lastOut    = lastBookedJson,
               @paused     = CASE WHEN staffPausedUntil > @now THEN 1 ELSE 0 END
        FROM [dbo].[whatsappConversations]
        WHERE channelId = @channelId AND customerPhone = @phone;

        SELECT ('{"result":[{"pending":' + ISNULL(@pendingOut, 'null')
                + ',"staffPaused":' + CASE WHEN @paused = 1 THEN 'true' ELSE 'false' END
                + ',"lastBooked":' + ISNULL(@lastOut, 'null') + '}]}') AS jsonResult;

    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
