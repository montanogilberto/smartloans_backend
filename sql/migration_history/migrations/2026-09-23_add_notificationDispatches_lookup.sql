-- =============================================================================
-- Add dbo.sp_notificationDispatches_lookup — idempotency + webhook lookups
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/notificationDispatch.py read dbo.notificationDispatches with
-- two raw SELECTs:
--   - _existing_resolved_dispatch: "already sent/confirmed?" idempotency
--     check before burning a Twilio/Azure call.
--   - update_dispatch_status_connector: find the dispatch a provider
--     callback (Twilio status webhook) refers to, by providerMessageId.
-- sp_notificationDispatches_one only looks up by notificationDispatchId, so
-- neither fit. Backend rule: modules never issue raw SQL.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Same shape as sp_notificationDispatches_one: @pjsonfile VARCHAR(MAX),
--     root key notificationDispatches, ROOT('notificationDispatches').
--   - action 'resolved' (companyId, sourceType, sourceId, eventName):
--       latest dispatch in status sent|confirmed, or [] if none.
--   - action 'byProviderMessageId' (providerMessageId):
--       notificationDispatchId + companyId. No companyId input: the caller is
--       a provider webhook that only knows the provider's message id — the
--       row's own companyId is returned so the follow-up update is scoped.
--   - Dates as ISO-8601 (CONVERT 126); NULL stays null.
--   - Old raw SELECT TOP 1 had no ORDER BY; now newest-first (deterministic).
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_notificationDispatches_lookup] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @action            NVARCHAR(40),
        @companyId         INT,
        @sourceType        NVARCHAR(20),
        @sourceId          INT,
        @eventName         NVARCHAR(40),
        @providerMessageId NVARCHAR(100);

    SELECT TOP 1
        @action            = JSON_VALUE(value, '$.action'),
        @companyId         = TRY_CONVERT(INT, JSON_VALUE(value, '$.companyId')),
        @sourceType        = JSON_VALUE(value, '$.sourceType'),
        @sourceId          = TRY_CONVERT(INT, JSON_VALUE(value, '$.sourceId')),
        @eventName         = JSON_VALUE(value, '$.eventName'),
        @providerMessageId = JSON_VALUE(value, '$.providerMessageId')
    FROM OPENJSON(@pjsonfile, '$.notificationDispatches');

    IF @action = 'resolved'
    BEGIN
        SELECT TOP 1
            notificationDispatchId,
            selectedChannel,
            status,
            providerMessageId,
            CONVERT(VARCHAR(30), sentAt, 126)      AS sentAt,
            CONVERT(VARCHAR(30), confirmedAt, 126) AS confirmedAt
        FROM dbo.notificationDispatches
        WHERE companyId  = @companyId
          AND sourceType = @sourceType
          AND sourceId   = @sourceId
          AND eventName  = @eventName
          AND status IN ('sent', 'confirmed')
        ORDER BY notificationDispatchId DESC
        FOR JSON PATH, ROOT('notificationDispatches'), INCLUDE_NULL_VALUES;
    END
    ELSE IF @action = 'byProviderMessageId'
    BEGIN
        SELECT TOP 1
            notificationDispatchId,
            companyId
        FROM dbo.notificationDispatches
        WHERE providerMessageId = @providerMessageId
        ORDER BY notificationDispatchId DESC
        FOR JSON PATH, ROOT('notificationDispatches');
    END
    ELSE
        SELECT '{"error":"unknown action"}' AS [notificationDispatches];
END
GO
