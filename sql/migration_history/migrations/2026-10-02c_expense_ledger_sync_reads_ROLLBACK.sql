-- ROLLBACK for 2026-10-02c_expense_ledger_sync_reads.sql
-- Deploy a backend without the SP-based _fetch_expense /
-- _fetch_posted_expense_entries first, or every expense edit/delete fails
-- its ledger-sync hook (the expense itself still saves).

IF OBJECT_ID(N'dbo.sp_journalEntries_byReference', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_journalEntries_byReference];
GO
IF OBJECT_ID(N'dbo.sp_expense_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_expense_one];
GO
