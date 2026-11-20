-- ============================================================
-- ROLLBACK de 2026-11-20_post_term_interest.sql (RFC-019)
--
-- DESTRUCTIVO: borra las filas de interés posterior al plazo
-- (installmentType = 'POST_TERM_INTEREST') y la tasa guardada en loans.
-- Antes de correrlo, respaldar:
--   SELECT * FROM loanInstallments WHERE installmentType = 'POST_TERM_INTEREST';
--   SELECT loanId, paymentPlan, postTermRate FROM loans WHERE paymentPlan <> 'standard';
-- Orden: 1) volver a desplegar las versiones anteriores de sql/sp_loans.sql y
--        sql/sp_walletAndPayments.sql  2) este script.
-- ============================================================

IF COL_LENGTH('dbo.loanInstallments', 'installmentType') IS NOT NULL
    EXEC('DELETE FROM [dbo].[loanInstallments] WHERE installmentType = ''POST_TERM_INTEREST''');
GO

IF EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_loanInstallments_postTermPeriod')
    DROP INDEX UQ_loanInstallments_postTermPeriod ON [dbo].[loanInstallments];
GO
IF EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_loanInstallments_installmentType')
    ALTER TABLE [dbo].[loanInstallments] DROP CONSTRAINT CK_loanInstallments_installmentType;
GO
IF EXISTS (SELECT * FROM sys.default_constraints WHERE name = 'DF_loanInstallments_installmentType')
    ALTER TABLE [dbo].[loanInstallments] DROP CONSTRAINT DF_loanInstallments_installmentType;
GO
IF COL_LENGTH('dbo.loanInstallments', 'installmentType') IS NOT NULL
    ALTER TABLE [dbo].[loanInstallments] DROP COLUMN installmentType;
GO
IF COL_LENGTH('dbo.loanInstallments', 'interestPeriodStart') IS NOT NULL
    ALTER TABLE [dbo].[loanInstallments] DROP COLUMN interestPeriodStart;
GO
IF COL_LENGTH('dbo.loanInstallments', 'interestPeriodEnd') IS NOT NULL
    ALTER TABLE [dbo].[loanInstallments] DROP COLUMN interestPeriodEnd;
GO

IF EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_loans_postTermRate')
    ALTER TABLE [dbo].[loans] DROP CONSTRAINT CK_loans_postTermRate;
GO
IF EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_loans_paymentPlan')
    ALTER TABLE [dbo].[loans] DROP CONSTRAINT CK_loans_paymentPlan;
GO
IF EXISTS (SELECT * FROM sys.default_constraints WHERE name = 'DF_loans_paymentPlan')
    ALTER TABLE [dbo].[loans] DROP CONSTRAINT DF_loans_paymentPlan;
GO
IF COL_LENGTH('dbo.loans', 'postTermRate') IS NOT NULL
    ALTER TABLE [dbo].[loans] DROP COLUMN postTermRate;
GO
IF COL_LENGTH('dbo.loans', 'paymentPlan') IS NOT NULL
    ALTER TABLE [dbo].[loans] DROP COLUMN paymentPlan;
GO
