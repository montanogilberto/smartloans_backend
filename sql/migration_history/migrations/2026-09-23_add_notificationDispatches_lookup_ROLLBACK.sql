-- ROLLBACK for 2026-09-23_add_notificationDispatches_lookup.sql
-- Restore the raw-SQL _existing_resolved_dispatch and providerMessageId
-- lookup in modules/notificationDispatch.py first, or every dispatch and
-- every provider status callback fails.

IF OBJECT_ID(N'dbo.sp_notificationDispatches_lookup', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_notificationDispatches_lookup];
GO
