-- =============================================================================
-- Add dbo.posSupportConversations / dbo.posSupportMessages + sp_posSupportChat
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: new "Soporte POS" chat, distinct from the existing loanChat (borrower/
-- lender loan negotiation) — a POS cashier/admin chatting with a topic-scoped
-- support agent (Clientes now; Income/Expenses/Accounting planned later, see
-- LoanAgents_SmartLoans' agents/pos_clients_support). Deliberately a much
-- simpler schema than loanConversations/loanMessages: no borrower/lender
-- roles, no proposal/amount/rate fields — just one user, one topic, messages.
--
-- SCOPE:
--   - dbo.posSupportConversations: one row per (companyId, userId, topic) —
--     reused across messages the same way loanChat reuses an 'open' thread.
--   - dbo.posSupportMessages: senderRole 'user'|'agent'.
--   - sp_posSupportChat actions: start_conversation | send_message |
--     list_messages | list_conversations — same @pjsonfile/JSON-result shape
--     as sp_loanChat (single-row FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), so
--     modules/posSupportChat.py's _sp() helper is a straight copy of
--     modules/loanChat.py's.
--   - topic is free-text NVARCHAR(20), not a CHECK-constrained enum: new
--     topics (income/expenses/accounting) are additive, no migration needed
--     to add one — validation of which topics are actually wired to an agent
--     lives in the backend module, not the schema.
-- Idempotent: CREATE OR ALTER is always safe to re-run; tables guarded by
-- sys.tables existence checks.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posSupportConversations')
CREATE TABLE [dbo].[posSupportConversations] (
    conversationId  INT IDENTITY PRIMARY KEY,
    companyId       INT NOT NULL,
    userId          INT NOT NULL,
    topic           NVARCHAR(20) NOT NULL,     -- 'clients' | 'income' | 'expenses' | 'accounting'
    status          NVARCHAR(20) NOT NULL DEFAULT 'open',
    lastMessageAt   DATETIME2 NULL,
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2 NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'posSupportMessages')
CREATE TABLE [dbo].[posSupportMessages] (
    messageId       INT IDENTITY PRIMARY KEY,
    conversationId  INT NOT NULL,
    senderRole      NVARCHAR(10) NOT NULL,     -- 'user' | 'agent'
    body            NVARCHAR(MAX) NULL,
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE()
)
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
    ELSE IF @action = 'list_messages'
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
