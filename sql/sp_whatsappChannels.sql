-- ============================================================
-- WhatsApp numbers (Cloud API) and the company/branch each one belongs to.
-- The webhook resolves every inbound message with action 5 (by Meta's
-- phoneNumberId); admin screens use 0/1/2.
-- Table: sql/migrations/2026-09-28_whatsapp_channels.sql
-- ============================================================

IF OBJECT_ID('dbo.sp_whatsappChannels', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_whatsappChannels;
GO
CREATE PROCEDURE [dbo].[sp_whatsappChannels]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @action        INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].action'));
        DECLARE @channelId     INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].channelId'));
        DECLARE @phoneNumberId NVARCHAR(32) =                  JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].phoneNumberId');
        DECLARE @wabaId        NVARCHAR(32) =                  JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].wabaId');
        DECLARE @display       NVARCHAR(20) =                  JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].displayPhoneNumber');
        DECLARE @companyId     INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].companyId'));
        DECLARE @branchId      INT          = TRY_CONVERT(INT, JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].branchId'));
        DECLARE @tokenRef      NVARCHAR(64) =                  JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].accessTokenRef');
        DECLARE @botEnabled    BIT          = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].botEnabled'));
        DECLARE @isActive      BIT          = TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.whatsappChannels[0].isActive'));

        -- ── 5: webhook lookup by Meta phoneNumberId (active channels only) ──
        IF @action = 5
        BEGIN
            DECLARE @oneJson NVARCHAR(MAX) = (
                SELECT c.channelId, c.phoneNumberId, c.wabaId, c.displayPhoneNumber,
                       c.companyId, co.name AS companyName,
                       c.branchId, b.name AS branchName,
                       c.accessTokenRef, c.botEnabled
                FROM [dbo].[whatsappChannels] c
                LEFT JOIN [dbo].[companies] co ON co.companyId = c.companyId
                LEFT JOIN [dbo].[companiesBranch] b ON b.branchId = c.branchId
                WHERE c.phoneNumberId = @phoneNumberId AND c.isActive = 1
                FOR JSON PATH, INCLUDE_NULL_VALUES
            );
            SELECT ('{"result":[{"whatsappChannels":' + ISNULL(@oneJson, '[]') + '}]}') AS jsonResult;
            RETURN;
        END

        IF @companyId IS NULL
        BEGIN
            SELECT '{"error":"companyId is required"}' AS jsonResult;
            RETURN;
        END

        -- ── 1: register a number (or re-point it, matched by phoneNumberId) ─
        IF @action = 1
        BEGIN
            IF @phoneNumberId IS NULL
            BEGIN
                SELECT '{"error":"phoneNumberId is required"}' AS jsonResult;
                RETURN;
            END
            IF @branchId IS NOT NULL AND NOT EXISTS (
                SELECT 1 FROM [dbo].[companiesBranch] WHERE branchId = @branchId AND companyId = @companyId)
            BEGIN
                SELECT '{"error":"branchId does not belong to companyId"}' AS jsonResult;
                RETURN;
            END
            UPDATE [dbo].[whatsappChannels]
            SET wabaId = @wabaId, displayPhoneNumber = @display, companyId = @companyId,
                branchId = @branchId, accessTokenRef = @tokenRef,
                botEnabled = ISNULL(@botEnabled, botEnabled), isActive = 1, updatedAt = GETUTCDATE()
            WHERE phoneNumberId = @phoneNumberId;
            IF @@ROWCOUNT = 0
                INSERT INTO [dbo].[whatsappChannels]
                    (phoneNumberId, wabaId, displayPhoneNumber, companyId, branchId, accessTokenRef, botEnabled)
                VALUES (@phoneNumberId, @wabaId, @display, @companyId, @branchId, @tokenRef, ISNULL(@botEnabled, 1));
        END

        -- ── 2: switch the bot / the channel on or off ────────────────────────
        ELSE IF @action = 2
        BEGIN
            UPDATE [dbo].[whatsappChannels]
            SET botEnabled = ISNULL(@botEnabled, botEnabled),
                isActive   = ISNULL(@isActive, isActive),
                updatedAt  = GETUTCDATE()
            WHERE channelId = @channelId AND companyId = @companyId;
        END

        -- ── 0 / NULL (and after writes): the company's numbers ───────────────
        DECLARE @listJson NVARCHAR(MAX) = (
            SELECT c.channelId, c.phoneNumberId, c.wabaId, c.displayPhoneNumber,
                   c.companyId, c.branchId, b.name AS branchName,
                   c.accessTokenRef, c.botEnabled, c.isActive
            FROM [dbo].[whatsappChannels] c
            LEFT JOIN [dbo].[companiesBranch] b ON b.branchId = c.branchId
            WHERE c.companyId = @companyId
            ORDER BY c.channelId
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SELECT ('{"result":[{"whatsappChannels":' + ISNULL(@listJson, '[]') + '}]}') AS jsonResult;

    END TRY
    BEGIN CATCH
        DECLARE @Err NVARCHAR(500) = ERROR_MESSAGE();
        SELECT ('{"error":"' + REPLACE(@Err, '"', '''') + '"}') AS jsonResult;
    END CATCH
END
GO
