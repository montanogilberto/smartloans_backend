-- ROLLBACK for 2026-09-23_add_income_one.sql
-- Restore modules/income.py's raw-SQL _get_final_total_and_discount first,
-- or the income comprobante falls back to the client-submitted total.

IF OBJECT_ID(N'dbo.sp_income_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_income_one];
GO
