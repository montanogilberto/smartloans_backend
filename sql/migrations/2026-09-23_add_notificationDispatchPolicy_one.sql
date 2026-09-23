-- =============================================================================
-- Add dbo.sp_notificationDispatchPolicy_one — channel policy for one eventName
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: modules/notificationDispatch.py::_get_policy read
-- dbo.notificationDispatch_policy with a raw
-- "SELECT channel_list_json, allow_sms_fallback ... WHERE eventName = %s".
-- Backend rule: modules never issue raw SQL — every read goes through an SP.
--
-- SCOPE: one new read-only SP, no table/column changes.
--   - Same shape as sp_notificationDispatches_one: @pjsonfile VARCHAR(MAX),
--     FOR JSON AUTO, ROOT(...). Caller passes
--     {"notificationDispatchPolicies":[{"eventName":"income_created"}]}.
--   - channel_list_json is returned as the stored string; the module parses
--     it (unchanged behavior: malformed JSON -> no channels).
--   - No companyId: notificationDispatch_policy is global per eventName
--     (PK = eventName), not tenant data.
-- Idempotent: CREATE OR ALTER is always safe to re-run.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROC [dbo].[sp_notificationDispatchPolicy_one] (@pjsonfile VARCHAR(MAX))
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @eventName NVARCHAR(40);
    SET @eventName = (
        SELECT TOP 1 JSON_VALUE(value, '$.eventName')
        FROM OPENJSON(@pjsonfile, '$.notificationDispatchPolicies')
    );

    SELECT
        [eventName],
        [channel_list_json],
        CAST([allow_sms_fallback] AS BIT) AS allow_sms_fallback
    FROM dbo.notificationDispatch_policy
    WHERE eventName = @eventName
    FOR JSON AUTO, ROOT('notificationDispatchPolicies');
END
GO
