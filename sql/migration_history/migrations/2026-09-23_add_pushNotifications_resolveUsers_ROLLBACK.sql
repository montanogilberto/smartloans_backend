-- ROLLBACK for 2026-09-23_add_pushNotifications_resolveUsers.sql
-- Restore the raw-SQL clientId -> userId lookups in modules/pushNotifications.py,
-- modules/notificationDispatch.py and modules/automatedPayments.py first, or
-- pushes to clients stop resolving (they fall back to an empty tag / no push).

IF OBJECT_ID(N'dbo.sp_pushNotifications_resolveUsers', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_pushNotifications_resolveUsers];
GO
