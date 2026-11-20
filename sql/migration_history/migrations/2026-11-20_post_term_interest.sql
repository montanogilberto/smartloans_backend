-- ============================================================
-- 2026-11-20 — Interés posterior al plazo (RFC-019, POSVending
-- docs/rfcs/RFC-019-interest-free-post-term-interest.md)
--
-- Por qué: un préstamo con plan 'interest_free' se crea al 0 % (cuotas
-- iguales de monto / plazo); el capital que quede sin pagar al vencer la
-- última cuota genera la tasa anual pactada. El préstamo debe recordar esa
-- tasa y el calendario necesita filas de interés por periodo.
--
--   loans.paymentPlan            'standard' | 'interest_free'
--   loans.postTermRate           tasa anual % posterior al plazo (NULL en standard)
--   loanInstallments.installmentType      'REGULAR' | 'POST_TERM_INTEREST'
--   loanInstallments.interestPeriodStart / interestPeriodEnd  periodo cobrado
--
-- Quién escribe/lee:
--   sp_loans (create escribe paymentPlan/postTermRate; create/one/all los devuelven)
--   sp_loanInstallments (insert/list/due/post_term_candidates/insert_post_term_interest)
--   modules/automatedPayments.py (accrue_post_term_interest, post_term_interest_status)
--
-- Orden: 1) este script  2) sql/sp_loans.sql  3) sql/sp_walletAndPayments.sql
--        DEV -> QA -> PROD. Backend después; la app al final.
-- Rollback: 2026-11-20_post_term_interest_ROLLBACK.sql
-- Filas existentes: loans quedan 'standard', cuotas quedan 'REGULAR'. Idempotente.
-- ============================================================

-- ── loans ───────────────────────────────────────────────────
IF COL_LENGTH('dbo.loans', 'paymentPlan') IS NULL
    ALTER TABLE [dbo].[loans] ADD paymentPlan NVARCHAR(20) NOT NULL
        CONSTRAINT DF_loans_paymentPlan DEFAULT 'standard';
GO

IF COL_LENGTH('dbo.loans', 'postTermRate') IS NULL
    ALTER TABLE [dbo].[loans] ADD postTermRate DECIMAL(5,2) NULL;
GO

IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_loans_paymentPlan')
    ALTER TABLE [dbo].[loans]
        ADD CONSTRAINT CK_loans_paymentPlan CHECK (paymentPlan IN ('standard', 'interest_free'));
GO

-- standard -> sin tasa posterior; interest_free -> tasa obligatoria >= 0
IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_loans_postTermRate')
    ALTER TABLE [dbo].[loans]
        ADD CONSTRAINT CK_loans_postTermRate CHECK (
            (paymentPlan = 'standard' AND postTermRate IS NULL)
         OR (paymentPlan = 'interest_free' AND postTermRate IS NOT NULL AND postTermRate >= 0));
GO

-- ── loanInstallments ────────────────────────────────────────
IF COL_LENGTH('dbo.loanInstallments', 'installmentType') IS NULL
    ALTER TABLE [dbo].[loanInstallments] ADD installmentType NVARCHAR(20) NOT NULL
        CONSTRAINT DF_loanInstallments_installmentType DEFAULT 'REGULAR';
GO

IF COL_LENGTH('dbo.loanInstallments', 'interestPeriodStart') IS NULL
    ALTER TABLE [dbo].[loanInstallments] ADD interestPeriodStart DATE NULL;
GO

IF COL_LENGTH('dbo.loanInstallments', 'interestPeriodEnd') IS NULL
    ALTER TABLE [dbo].[loanInstallments] ADD interestPeriodEnd DATE NULL;
GO

IF NOT EXISTS (SELECT * FROM sys.check_constraints WHERE name = 'CK_loanInstallments_installmentType')
    ALTER TABLE [dbo].[loanInstallments]
        ADD CONSTRAINT CK_loanInstallments_installmentType
            CHECK (installmentType IN ('REGULAR', 'POST_TERM_INTEREST'));
GO

-- Un periodo de interés se cobra una sola vez (job idempotente).
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'UQ_loanInstallments_postTermPeriod')
    CREATE UNIQUE INDEX UQ_loanInstallments_postTermPeriod
        ON [dbo].[loanInstallments] (loanId, installmentNumber)
        WHERE installmentType = 'POST_TERM_INTEREST';
GO
