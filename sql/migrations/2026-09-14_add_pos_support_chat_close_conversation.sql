-- =============================================================================
-- Add a close_conversation action to sp_posSupportChat ("clear history")
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: start_conversation reuses the caller's existing 'open' thread for a
-- topic indefinitely — there was no way to end one and start fresh. Marks
-- the given conversation 'closed'; the next start_conversation for that
-- (companyId, userId, topic) will then create a genuinely new one (existing
-- logic, unchanged). Scoped by companyId + userId, same ownership check as
-- the 2026-09-14 list_messages fix — a caller can only close their own
-- conversation.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_posSupportChat]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)  = JSON_VALUE(@pjsonfile, '$.chat[0].action')
    DECLARE @companyId       INT           = JSON_VALUE(@pjsonfile, '$.chat[0].companyId')
    DECLARE @conversationId  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].conversationId')
    DECLARE @userId          INT           = JSON_VALUE(@pjsonfile, '$.chat[0].userId')
    DECLARE @topic           NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.chat[0].topic')

    IF @action = 'start_conversation'
    BEGIN
        IF EXISTS (
            SELECT 1 FROM posSupportConversations
            WHERE companyId = @companyId AND userId = @userId
              AND topic = @topic AND status = 'open'
        )
        BEGIN
            SELECT (SELECT TOP 1 conversationId, companyId, userId, topic,
                status, lastMessageAt, created_At
                FROM posSupportConversations
                WHERE companyId = @companyId AND userId = @userId
                  AND topic = @topic AND status = 'open'
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
        ELSE
        BEGIN
            INSERT INTO posSupportConversations
                (companyId, userId, topic, lastMessageAt)
            VALUES
                (@companyId, @userId, @topic, GETUTCDATE())

            DECLARE @newConvId INT = SCOPE_IDENTITY()
            SELECT (SELECT conversationId, companyId, userId, topic,
                status, created_At
                FROM posSupportConversations WHERE conversationId = @newConvId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
    END

    ELSE IF @action = 'send_message'
    BEGIN
        DECLARE @senderRole NVARCHAR(10)  = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')
        DECLARE @body       NVARCHAR(MAX) = JSON_VALUE(@pjsonfile, '$.chat[0].body')

        INSERT INTO posSupportMessages (conversationId, senderRole, body)
        VALUES (@conversationId, @senderRole, @body)

        DECLARE @newMsgId INT = SCOPE_IDENTITY()

        UPDATE posSupportConversations
        SET lastMessageAt = GETUTCDATE(), updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId

        SELECT (SELECT @newMsgId AS messageId, @conversationId AS conversationId,
            @senderRole AS senderRole, @body AS body
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    ELSE IF @action = 'list_messages'
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM posSupportConversations
            WHERE conversationId = @conversationId
              AND companyId = @companyId AND userId = @userId
        )
        BEGIN
            SELECT '[]' AS [jsonResult]
        END
        ELSE
        BEGIN
            SELECT ISNULL(
                (SELECT messageId, conversationId, senderRole, body, created_At
                    FROM posSupportMessages
                    WHERE conversationId = @conversationId
                    ORDER BY messageId
                    FOR JSON PATH),
                '[]'
            ) AS [jsonResult]
        END
    END

    ELSE IF @action = 'list_conversations'
    BEGIN
        SELECT ISNULL(
            (SELECT conversationId, companyId, userId, topic, status,
                lastMessageAt, created_At
                FROM posSupportConversations
                WHERE companyId = @companyId AND userId = @userId
                ORDER BY lastMessageAt DESC
                FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── close_conversation ("clear history") ─────────────────
    -- Scoped the same way as list_messages: only the owning (companyId,
    -- userId) can close it. Silently no-ops if it doesn't belong to the
    -- caller or doesn't exist — same "don't confirm/deny" posture as
    -- list_messages, rather than raising an error.
    ELSE IF @action = 'close_conversation'
    BEGIN
        UPDATE posSupportConversations
        SET status = 'closed', updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId
          AND companyId = @companyId AND userId = @userId
          AND status = 'open'

        SELECT (SELECT @conversationId AS conversationId, 'closed' AS status
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
