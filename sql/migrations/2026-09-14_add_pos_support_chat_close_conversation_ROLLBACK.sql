-- =============================================================================
-- ROLLBACK for 2026-09-14_add_pos_support_chat_close_conversation.sql
-- =============================================================================
-- Restores sp_posSupportChat to the version WITHOUT the close_conversation
-- action (i.e. back to the state after the list_messages-scoping fix, but
-- before "clear history" was added). Removing close_conversation means any
-- frontend "Nueva conversación" button calling it will get a generic SP
-- error (unrecognized action) until re-applied or the frontend change is
-- also reverted.
--
-- For reference, this is the list_messages ownership-scoping fix this
-- rollback preserves (still in effect after rolling back close_conversation):
-- list_messages requires @companyId/@userId and verifies ownership via
-- dbo.posSupportConversations before returning anything.
--
-- NOTE: this does NOT fix the deeper issue that companyId/userId are
-- entirely client-asserted with no server-side identity verification
-- anywhere on this route (no auth middleware, no Depends() check) — that
-- is a separate, codebase-wide problem, not unique to posSupportChat, and
-- is out of scope for this migration.
--
-- Idempotent: CREATE OR ALTER is always safe to re-run.
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

    -- ── start_conversation ───────────────────────────────────
    -- Reuses this user's existing open conversation for the topic, same
    -- one-open-thread-per-pair idiom as sp_loanChat's start_conversation.
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

    -- ── send_message ─────────────────────────────────────────
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

    -- ── list_messages ─────────────────────────────────────────
    -- FIXED: now requires @companyId/@userId and verifies ownership via
    -- posSupportConversations before returning anything. A mismatched
    -- conversationId (wrong owner, or one that doesn't exist) returns an
    -- empty list rather than an error, so this endpoint never confirms or
    -- denies the existence of a conversationId to a caller who can't see it.
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

    -- ── list_conversations ────────────────────────────────────
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

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
