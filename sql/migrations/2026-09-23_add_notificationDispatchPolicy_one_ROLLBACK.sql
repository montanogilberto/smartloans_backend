-- ROLLBACK for 2026-09-23_add_notificationDispatchPolicy_one.sql
-- Restore modules/notificationDispatch.py's raw-SQL _get_policy first, or
-- every dispatch returns 400 "No notificationDispatch_policy row".

IF OBJECT_ID(N'dbo.sp_notificationDispatchPolicy_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_notificationDispatchPolicy_one];
GO
