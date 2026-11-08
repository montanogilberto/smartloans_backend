-- RFC-010 Amendment A (POSVending docs/rfcs): a company the platform owns may charge
-- card top-ups on the platform's own Stripe account (accountType 'stripe_platform').
-- Which companies may do so is decided in code (PLATFORM_TOPUP_COMPANIES).
-- Idempotent: safe to run more than once. Run before sql/sp_companyPaymentAccounts.sql.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints
           WHERE name = 'CK_companyPaymentAccounts_type'
             AND parent_object_id = OBJECT_ID('dbo.companyPaymentAccounts')
             AND definition NOT LIKE '%stripe_platform%')
    ALTER TABLE dbo.companyPaymentAccounts DROP CONSTRAINT CK_companyPaymentAccounts_type;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints
               WHERE name = 'CK_companyPaymentAccounts_type'
                 AND parent_object_id = OBJECT_ID('dbo.companyPaymentAccounts'))
    ALTER TABLE dbo.companyPaymentAccounts ADD CONSTRAINT CK_companyPaymentAccounts_type
        CHECK (accountType IN ('spei', 'stripe_connect', 'stripe_platform'));
GO
