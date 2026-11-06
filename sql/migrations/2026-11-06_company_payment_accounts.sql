-- =============================================================================
-- companyPaymentAccounts: accounts that receive money for a COMPANY, so card
-- top-ups land in the company's own Stripe account and never in SmartLoans'
-- (architecture D1, RFC-010). Base table comes from the factory PRD
-- companyPaymentAccount. Its stored procedures are in sql/sp_companyPaymentAccounts.sql.
--
-- Rows are never deleted. PENDING_VERIFICATION -> ACTIVE (second admin) -> ARCHIVED.
-- The CLABE and holder are entered in the POS, never written in this repo (it is public).
-- =============================================================================
-- Filtered indexes need these ON, and the SP stores them when it is created.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.companyPaymentAccounts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.companyPaymentAccounts (
        companyPaymentAccountId  INT IDENTITY(1,1) NOT NULL,
        companyId                INT NOT NULL,
        commissionTerminalId     INT NULL,       -- the terminal this account belongs to, per company
        purpose                  NVARCHAR(30) NOT NULL,
        accountType              NVARCHAR(20) NOT NULL,
        accountStatus            NVARCHAR(22) NOT NULL,
        clabe                    NVARCHAR(18) NULL,
        clabeHash                NVARCHAR(64) NULL,
        bankCode                 NVARCHAR(5) NULL,
        bankName                 NVARCHAR(100) NULL,
        holderName               NVARCHAR(255) NOT NULL,
        rfc                      NVARCHAR(13) NULL,
        stripeConnectedAccountId NVARCHAR(100) NULL,
        chargesEnabled           BIT NULL,
        createdByUserId          INT NOT NULL,   -- no FK: dbo.users has no primary key
        verifiedByUserId         INT NULL,
        verifiedAt               DATETIME NULL,
        archivedAt               DATETIME NULL,
        notes                    NVARCHAR(255) NULL,
        created_At               DATETIME NOT NULL CONSTRAINT DF_companyPaymentAccounts_created DEFAULT GETDATE(),
        updated_at               DATETIME NULL,
        CONSTRAINT PK_companyPaymentAccounts PRIMARY KEY CLUSTERED (companyPaymentAccountId),
        CONSTRAINT FK_companyPaymentAccounts_companies FOREIGN KEY (companyId) REFERENCES dbo.companies (companyId),
        CONSTRAINT FK_companyPaymentAccounts_terminal FOREIGN KEY (commissionTerminalId) REFERENCES dbo.commissionTerminals (commissionTerminalId),
        CONSTRAINT CK_companyPaymentAccounts_status CHECK (accountStatus IN ('PENDING_VERIFICATION', 'ACTIVE', 'ARCHIVED')),
        CONSTRAINT CK_companyPaymentAccounts_type CHECK (accountType IN ('spei', 'stripe_connect'))
    );
    CREATE INDEX IX_companyPaymentAccounts_company ON dbo.companyPaymentAccounts (companyId, purpose, accountType);
    -- At most one ACTIVE account per company, purpose and type.
    CREATE UNIQUE INDEX UX_companyPaymentAccounts_active ON dbo.companyPaymentAccounts (companyId, purpose, accountType)
        WHERE accountStatus = 'ACTIVE';
    -- A Stripe account can never serve two companies.
    CREATE UNIQUE INDEX UX_companyPaymentAccounts_stripe ON dbo.companyPaymentAccounts (stripeConnectedAccountId)
        WHERE stripeConnectedAccountId IS NOT NULL;
END
GO

-- For a table created before this column existed (the CREATE above is skipped).
IF COL_LENGTH('dbo.companyPaymentAccounts', 'commissionTerminalId') IS NULL
    ALTER TABLE dbo.companyPaymentAccounts ADD commissionTerminalId INT NULL;
GO

IF OBJECT_ID('dbo.FK_companyPaymentAccounts_terminal', 'F') IS NULL
    ALTER TABLE dbo.companyPaymentAccounts ADD CONSTRAINT FK_companyPaymentAccounts_terminal
        FOREIGN KEY (commissionTerminalId) REFERENCES dbo.commissionTerminals (commissionTerminalId);
GO

-- The app reads role features from these tables, so without this grant no admin
-- would see Cuentas de cobro, whatever rolePermissions.ts says.
INSERT INTO dbo.uiFeatures (featureCode, displayName, moduleCode)
SELECT 'companyPaymentAccounts', 'Cuentas de cobro', 'pos'
WHERE NOT EXISTS (SELECT 1 FROM dbo.uiFeatures WHERE featureCode = 'companyPaymentAccounts');

INSERT INTO dbo.roleUiFeatures (roleId, featureId)
SELECT r.roleId, f.featureId
FROM dbo.roles r
JOIN dbo.uiFeatures f ON f.featureCode = 'companyPaymentAccounts'
WHERE r.code IN ('admin', 'manager')
  AND NOT EXISTS (SELECT 1 FROM dbo.roleUiFeatures ruf WHERE ruf.roleId = r.roleId AND ruf.featureId = f.featureId);
GO
