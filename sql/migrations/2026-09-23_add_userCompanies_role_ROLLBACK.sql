-- ROLLBACK for 2026-09-23_add_userCompanies_role.sql
-- Restore the raw-SQL _requester_role in modules/fundingTransactions.py
-- first, or every resolve_escalation request is rejected with 403.

IF OBJECT_ID(N'dbo.sp_userCompanies_role', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_userCompanies_role];
GO
