-- ============================================================
-- Loan Chat — conversational loan negotiation
-- Tables:   loanConversations, loanMessages
-- SP:       sp_loanChat
-- Actions:  start_conversation | send_message | list_messages
--           mark_read | accept_proposal | reject_proposal
--           list_conversations | get_conversation
-- ============================================================

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'loanConversations')
CREATE TABLE [dbo].[loanConversations] (
    conversationId  INT IDENTITY PRIMARY KEY,
    companyId       INT NOT NULL,
    borrowerId      INT NOT NULL,          -- clientId of borrower
    lenderId        INT NOT NULL,          -- clientId of lender
    borrowerUserId  INT NULL,              -- userId for push targeting
    lenderUserId    INT NULL,
    loanProposalId  INT NULL,              -- linked proposal once accepted
    status          NVARCHAR(20) NOT NULL DEFAULT 'open',
                                           -- open | accepted | rejected | closed
    requestedAmount DECIMAL(14,2) NULL,
    agreedAmount    DECIMAL(14,2) NULL,
    agreedRate      DECIMAL(6,4) NULL,
    agreedTermMonths INT NULL,
    title           NVARCHAR(200) NULL,
    lastMessageAt   DATETIME2 NULL,
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    updated_at      DATETIME2 NULL
)
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'loanMessages')
CREATE TABLE [dbo].[loanMessages] (
    messageId       INT IDENTITY PRIMARY KEY,
    conversationId  INT NOT NULL,
    senderId        INT NOT NULL,          -- clientId of sender
    senderUserId    INT NULL,
    senderRole      NVARCHAR(20) NOT NULL, -- borrower | lender
    msgType         NVARCHAR(20) NOT NULL DEFAULT 'text',
                                           -- text | proposal | counter | accept | reject | system
    body            NVARCHAR(2000) NULL,
    amount          DECIMAL(14,2) NULL,
    rate            DECIMAL(6,4) NULL,
    termMonths      INT NULL,
    isRead          BIT NOT NULL DEFAULT 0,
    pushSent        BIT NOT NULL DEFAULT 0,
    created_At      DATETIME2 NOT NULL DEFAULT GETUTCDATE()
)
GO

-- ── SP ───────────────────────────────────────────────────────

IF OBJECT_ID('dbo.sp_loanChat', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_loanChat;
GO

CREATE PROCEDURE [dbo].[sp_loanChat]
    @pjsonfile NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

    DECLARE @action          NVARCHAR(40)   = JSON_VALUE(@pjsonfile, '$.chat[0].action')
    DECLARE @companyId       INT            = JSON_VALUE(@pjsonfile, '$.chat[0].companyId')
    DECLARE @conversationId  INT            = JSON_VALUE(@pjsonfile, '$.chat[0].conversationId')
    DECLARE @clientId        INT            = JSON_VALUE(@pjsonfile, '$.chat[0].clientId')
    DECLARE @userId          INT            = JSON_VALUE(@pjsonfile, '$.chat[0].userId')

    -- ── start_conversation ───────────────────────────────────
    IF @action = 'start_conversation'
    BEGIN
        DECLARE @borrowerId      INT           = JSON_VALUE(@pjsonfile, '$.chat[0].borrowerId')
        DECLARE @lenderId        INT           = JSON_VALUE(@pjsonfile, '$.chat[0].lenderId')
        DECLARE @borrowerUserId  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].borrowerUserId')
        DECLARE @lenderUserId    INT           = JSON_VALUE(@pjsonfile, '$.chat[0].lenderUserId')
        DECLARE @requestedAmt    DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.chat[0].requestedAmount')
        DECLARE @title           NVARCHAR(200) = JSON_VALUE(@pjsonfile, '$.chat[0].title')

        -- Reuse existing open conversation between these two parties
        IF EXISTS (
            SELECT 1 FROM loanConversations
            WHERE companyId = @companyId AND borrowerId = @borrowerId
              AND lenderId = @lenderId AND status = 'open'
        )
        BEGIN
            SELECT (SELECT TOP 1 conversationId, companyId, borrowerId, lenderId,
                borrowerUserId, lenderUserId, status, requestedAmount, title,
                lastMessageAt, created_At
                FROM loanConversations
                WHERE companyId = @companyId AND borrowerId = @borrowerId
                  AND lenderId = @lenderId AND status = 'open'
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
        ELSE
        BEGIN
            INSERT INTO loanConversations
                (companyId, borrowerId, lenderId, borrowerUserId, lenderUserId,
                 requestedAmount, title, lastMessageAt)
            VALUES
                (@companyId, @borrowerId, @lenderId, @borrowerUserId, @lenderUserId,
                 @requestedAmt, @title, GETUTCDATE())

            DECLARE @newConvId INT = SCOPE_IDENTITY()
            SELECT (SELECT conversationId, companyId, borrowerId, lenderId,
                borrowerUserId, lenderUserId, status, requestedAmount, title, created_At
                FROM loanConversations WHERE conversationId = @newConvId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
        END
    END

    -- ── send_message ─────────────────────────────────────────
    ELSE IF @action = 'send_message'
    BEGIN
        DECLARE @senderId    INT           = JSON_VALUE(@pjsonfile, '$.chat[0].senderId')
        DECLARE @senderRole  NVARCHAR(20)  = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')
        DECLARE @msgType     NVARCHAR(20)  = ISNULL(JSON_VALUE(@pjsonfile, '$.chat[0].msgType'), 'text')
        DECLARE @body        NVARCHAR(2000)= JSON_VALUE(@pjsonfile, '$.chat[0].body')
        DECLARE @amount      DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.chat[0].amount')
        DECLARE @rate        DECIMAL(6,4)  = JSON_VALUE(@pjsonfile, '$.chat[0].rate')
        DECLARE @termMonths  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].termMonths')
        DECLARE @senderUserId INT          = JSON_VALUE(@pjsonfile, '$.chat[0].senderUserId')

        INSERT INTO loanMessages
            (conversationId, senderId, senderUserId, senderRole, msgType, body, amount, rate, termMonths)
        VALUES
            (@conversationId, @senderId, @senderUserId, @senderRole, @msgType, @body, @amount, @rate, @termMonths)

        DECLARE @newMsgId INT = SCOPE_IDENTITY()

        UPDATE loanConversations
        SET lastMessageAt = GETUTCDATE(), updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId

        -- Return message + target userId for push
        DECLARE @targetUserId INT
        SELECT @targetUserId =
            CASE WHEN borrowerId = @senderId THEN lenderUserId ELSE borrowerUserId END
        FROM loanConversations WHERE conversationId = @conversationId

        SELECT (SELECT @newMsgId AS messageId, @conversationId AS conversationId,
            @msgType AS msgType, @body AS body, @amount AS amount,
            @rate AS rate, @termMonths AS termMonths,
            @targetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    -- ── list_messages ─────────────────────────────────────────
    ELSE IF @action = 'list_messages'
    BEGIN
        SELECT ISNULL(
            (SELECT messageId, conversationId, senderId, senderRole, msgType,
                body, amount, rate, termMonths, isRead, pushSent, created_At
                FROM loanMessages
                WHERE conversationId = @conversationId
                ORDER BY messageId
                FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── mark_read ─────────────────────────────────────────────
    ELSE IF @action = 'mark_read'
    BEGIN
        UPDATE loanMessages
        SET isRead = 1
        WHERE conversationId = @conversationId AND senderId <> @clientId AND isRead = 0
        SELECT '{"updated":true}' AS [jsonResult]
    END

    -- ── accept_proposal ───────────────────────────────────────
    ELSE IF @action = 'accept_proposal'
    BEGIN
        DECLARE @agreedAmount    DECIMAL(14,2) = JSON_VALUE(@pjsonfile, '$.chat[0].amount')
        DECLARE @agreedRate      DECIMAL(6,4)  = JSON_VALUE(@pjsonfile, '$.chat[0].rate')
        DECLARE @agreedTerm      INT           = JSON_VALUE(@pjsonfile, '$.chat[0].termMonths')
        DECLARE @acceptSenderId  INT           = JSON_VALUE(@pjsonfile, '$.chat[0].senderId')
        DECLARE @acceptSenderRole NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')

        UPDATE loanConversations SET
            status          = 'accepted',
            agreedAmount    = @agreedAmount,
            agreedRate      = @agreedRate,
            agreedTermMonths = @agreedTerm,
            updated_at      = GETUTCDATE()
        WHERE conversationId = @conversationId

        INSERT INTO loanMessages
            (conversationId, senderId, senderUserId, senderRole, msgType, body, amount, rate, termMonths)
        VALUES
            (@conversationId, @acceptSenderId, @userId, @acceptSenderRole,
             'accept', '✅ Propuesta aceptada — préstamo en proceso.', @agreedAmount, @agreedRate, @agreedTerm)

        DECLARE @acceptTargetUserId INT
        SELECT @acceptTargetUserId =
            CASE WHEN borrowerId = @acceptSenderId THEN lenderUserId ELSE borrowerUserId END
        FROM loanConversations WHERE conversationId = @conversationId

        SELECT (SELECT @conversationId AS conversationId, 'accepted' AS status,
            @agreedAmount AS agreedAmount, @agreedRate AS agreedRate, @agreedTerm AS agreedTermMonths,
            @acceptTargetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    -- ── reject_proposal ───────────────────────────────────────
    ELSE IF @action = 'reject_proposal'
    BEGIN
        DECLARE @rejectSenderId   INT          = JSON_VALUE(@pjsonfile, '$.chat[0].senderId')
        DECLARE @rejectSenderRole NVARCHAR(20) = JSON_VALUE(@pjsonfile, '$.chat[0].senderRole')

        UPDATE loanConversations SET status = 'rejected', updated_at = GETUTCDATE()
        WHERE conversationId = @conversationId

        INSERT INTO loanMessages
            (conversationId, senderId, senderUserId, senderRole, msgType, body)
        VALUES
            (@conversationId, @rejectSenderId, @userId, @rejectSenderRole,
             'reject', '❌ Propuesta rechazada.')

        DECLARE @rejectTargetUserId INT
        SELECT @rejectTargetUserId =
            CASE WHEN borrowerId = @rejectSenderId THEN lenderUserId ELSE borrowerUserId END
        FROM loanConversations WHERE conversationId = @conversationId

        SELECT (SELECT @conversationId AS conversationId, 'rejected' AS status,
            @rejectTargetUserId AS targetUserId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER) AS [jsonResult]
    END

    -- ── list_conversations ────────────────────────────────────
    ELSE IF @action = 'list_conversations'
    BEGIN
        SELECT ISNULL(
            (SELECT conversationId, companyId, borrowerId, lenderId,
                borrowerUserId, lenderUserId, loanProposalId,
                status, requestedAmount, agreedAmount, agreedRate, agreedTermMonths,
                title, lastMessageAt, created_At
                FROM loanConversations
                WHERE companyId = @companyId
                  AND (borrowerId = @clientId OR lenderId = @clientId)
                ORDER BY lastMessageAt DESC
                FOR JSON PATH),
            '[]'
        ) AS [jsonResult]
    END

    -- ── get_conversation ──────────────────────────────────────
    ELSE IF @action = 'get_conversation'
    BEGIN
        SELECT ISNULL(
            (SELECT conversationId, companyId, borrowerId, lenderId,
                borrowerUserId, lenderUserId, loanProposalId,
                status, requestedAmount, agreedAmount, agreedRate, agreedTermMonths,
                title, lastMessageAt, created_At, updated_at
                FROM loanConversations
                WHERE conversationId = @conversationId
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'null'
        ) AS [jsonResult]
    END

    END TRY
    BEGIN CATCH
        SELECT '{"error":"' + REPLACE(ERROR_MESSAGE(), '"', '\"') + '"}' AS [jsonResult]
    END CATCH
END
GO
