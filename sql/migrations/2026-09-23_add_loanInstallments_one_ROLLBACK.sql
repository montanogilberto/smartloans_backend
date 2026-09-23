-- ROLLBACK for 2026-09-23_add_loanInstallments_one.sql
-- Restore the raw-SQL installment reads in modules/automatedPayments.py and
-- modules/rewardBenefits.py first, or SPEI installment payments 404 and
-- on-time reward points stop being granted.

IF OBJECT_ID(N'dbo.sp_loanInstallments_one', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_loanInstallments_one];
GO
