-- Rollback de 2026-11-20_loan_proposals_payment_plan.sql
-- Primero volver a desplegar la versión anterior de sql/sp_loanProposals.sql
-- (la nueva referencia paymentPlan y fallaría sin la columna).

IF EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_loanProposals_paymentPlan')
    ALTER TABLE [dbo].[loanProposals] DROP CONSTRAINT CK_loanProposals_paymentPlan;
GO
IF EXISTS (SELECT * FROM sys.default_constraints WHERE name = 'DF_loanProposals_paymentPlan')
    ALTER TABLE [dbo].[loanProposals] DROP CONSTRAINT DF_loanProposals_paymentPlan;
GO
IF COL_LENGTH('dbo.loanProposals', 'paymentPlan') IS NOT NULL
    ALTER TABLE [dbo].[loanProposals] DROP COLUMN paymentPlan;
GO
