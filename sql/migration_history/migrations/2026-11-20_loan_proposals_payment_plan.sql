-- ============================================================
-- 2026-11-20 — loanProposals.paymentPlan (préstamo sin intereses tipo tarjeta)
--
-- 'standard'      = amortización con interés (comportamiento actual).
-- 'interest_free' = 0% dentro del plazo; pago mínimo mensual = monto / plazo.
--                   proposedRate (o counteredRate) es la tasa anual que aplica
--                   al saldo que quede sin pagar al terminar el plazo.
--
-- Filas existentes quedan en 'standard'. Idempotente.
-- Después de esto, volver a desplegar sql/sp_loanProposals.sql (create y
-- _all leen/devuelven la columna nueva).
-- ============================================================

IF COL_LENGTH('dbo.loanProposals', 'paymentPlan') IS NULL
    ALTER TABLE [dbo].[loanProposals] ADD paymentPlan NVARCHAR(20) NOT NULL
        CONSTRAINT DF_loanProposals_paymentPlan DEFAULT 'standard';
GO

IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_loanProposals_paymentPlan')
    ALTER TABLE [dbo].[loanProposals]
        ADD CONSTRAINT CK_loanProposals_paymentPlan CHECK (paymentPlan IN ('standard', 'interest_free'));
GO
