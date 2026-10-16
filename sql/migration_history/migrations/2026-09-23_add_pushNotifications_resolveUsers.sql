-- =============================================================================
-- Add dbo.sp_pushNotifications_resolveUsers — map recipient ids -> userId
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: Azure Notification Hub tags devices as user_{userId}, but callers
-- routinely hold a CLIENT id. Three modules resolved clientId -> userId with
-- copy-pasted raw SQL ("SELECT TOP 1 userId FROM users WHERE clientId = %s"):
--   - modules/pushNotifications.py   (plus "SELECT 1 FROM users WHERE userId"
--                                     — 2 round-trips PER recipient)
--   - modules/notificationDispatch.py::_resolve_push_user_id
--   - modules/automatedPayments.py::pay_installment_spei (lender push)
-- Backend rule: modules never issue raw SQL. One set-based SP replaces all
-- of them and resolves a whole recipient list in a single call.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Same flat-payload style as sp_pushNotifications_activeUsers:
--       {"allowUserId": 1, "ids": [2167, 27]}
--     allowUserId = 1 -> an id that already IS a userId is kept as-is
--                        (pushNotifications: callers mix userIds/clientIds).
--     allowUserId = 0 -> every id is a clientId (dispatch, SPEI lender push).
--   - Returns one row per input id, in input order:
--       {"users":[{"id":2167,"userId":27,"resolvedBy":"client"}, ...]}
--     resolvedBy: "user" | "client" | null (no linked account).
--   - clientId match picks the lowest userId (the old TOP 1 had no ORDER BY,
--     so the pick was arbitrary when a client had several app accounts).
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE dbo.sp_pushNotifications_resolveUsers
    @pjsonfile VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @allowUserId BIT = ISNULL(TRY_CONVERT(BIT, JSON_VALUE(@pjsonfile, '$.allowUserId')), 0);

    SELECT
        TRY_CONVERT(INT, j.[value]) AS id,
        COALESCE(u.userId, c.userId) AS userId,
        CASE WHEN u.userId IS NOT NULL THEN 'user'
             WHEN c.userId IS NOT NULL THEN 'client'
        END AS resolvedBy
    FROM OPENJSON(@pjsonfile, '$.ids') j
    OUTER APPLY (
        SELECT u1.userId
        FROM dbo.users u1
        WHERE @allowUserId = 1
          AND u1.userId = TRY_CONVERT(INT, j.[value])
    ) u
    OUTER APPLY (
        SELECT TOP 1 u2.userId
        FROM dbo.users u2
        WHERE u2.clientId = TRY_CONVERT(INT, j.[value])
        ORDER BY u2.userId
    ) c
    ORDER BY TRY_CONVERT(INT, j.[key])
    FOR JSON PATH, ROOT('users'), INCLUDE_NULL_VALUES;
END;
GO
