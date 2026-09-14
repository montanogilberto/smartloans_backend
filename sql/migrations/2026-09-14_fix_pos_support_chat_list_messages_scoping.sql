-- =============================================================================
-- Fix sp_posSupportChat: list_messages had NO tenant/ownership scoping
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB (same convention as the
-- 2026-09-11 migration this fixes).
--
-- WHY: the original sp_posSupportChat's list_messages branch filtered ONLY
-- by @conversationId:
--
--     SELECT ... FROM posSupportMessages WHERE conversationId = @conversationId
--
-- start_conversation and list_conversations both correctly scope by
-- companyId + userId; list_messages did not. conversationId is a plain
-- auto-incrementing INT IDENTITY, so any authenticated caller could read
-- any OTHER user's or company's support-chat messages by requesting
-- conversationId = 1, 2, 3... — including client names/phone numbers today,
-- and real income/expense/accounting figures once those topics see traffic.
--
-- FIX: list_messages now requires @companyId and @userId (same as
-- start_conversation/list_conversations) and verifies the conversation
-- actually belongs to that (companyId, userId) pair via
-- dbo.posSupportConversations before returning anything — mismatched
-- ownership returns an empty list, not an error (avoids confirming/denying
-- whether a given conversationId exists to a caller who shouldn't see it).
--
-- CALLER IMPACT: modules/posSupportChat.py passes the request payload
-- through unchanged, so no Python change is needed there — but the
-- FRONTEND's posSupportChatApi.ts::listMessages() must now send companyId
-- and userId alongside conversationId (see accompanying frontend change).
-- A list_messages call that omits them will now always get back [].
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
