-- ROLLBACK for 2026-09-30_income_terminal_commission.sql
-- Deploy the previous backend first (modules/income.py without the
-- sp_income_applyCommission hook), or every card sale logs a hook failure.
-- NOTE: dropping the columns discards every stored commission snapshot.

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- sp_income_monthly back to 2026-09-29_income_monthly_any_month.sql
-- (re-run that file), then:

IF OBJECT_ID(N'dbo.sp_income_applyCommission', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_income_applyCommission];
GO

IF COL_LENGTH('dbo.income', 'commissionAmount') IS NOT NULL
    ALTER TABLE [dbo].[income] DROP COLUMN [commissionAmount];
GO
IF COL_LENGTH('dbo.income', 'commissionRatePct') IS NOT NULL
    ALTER TABLE [dbo].[income] DROP COLUMN [commissionRatePct];
GO
-- commissionTerminalId values written by the backfill are left in place
-- (the column predates this migration).
