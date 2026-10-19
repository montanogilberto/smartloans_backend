-- WhatsApp assistant content, per company with optional branch override.
-- The agent (LoanAgents_SmartLoans agents/whatsapp_reservations) answers
-- promotions / business info / FAQ questions ONLY from these tables — never
-- from its prompt — so each business edits its own content from the POS.
--
--   promotions     existing POS table (+ description) — what's on offer now
--   businessInfo   address, maps link, phone, payment methods, prices…
--                  one row per company (branchId NULL) + optional per-branch rows
--   businessFaqs   question/answer pairs the agent may quote
--
-- businessInfo / businessFaqs: branchId NULL = every branch of the company.
-- Run order: this file → sql/sp_businessInfo.sql → sql/sp_businessFaqs.sql,
-- directly in the database (sql/migrations/README_whatsapp_assistant.md).
-- sp_promotions / sp_whatsappCustomerRewards go with the POS rewards scripts.

-- Promotions: dbo.promotions ALREADY EXISTS — it is the table the POS applies
-- at checkout (sp_income / sp_income_apply_promo, e.g. code 2X1). The
-- assistant reads that same table so it never advertises a promotion the POS
-- can't apply. Only a customer-facing description is added (nullable; both
-- SPs list their columns explicitly, so they are unaffected).
-- Skipped once 2026-10-16d has dropped dbo.promotions (coupons live in the catalog).
IF OBJECT_ID('dbo.promotions', 'U') IS NOT NULL AND COL_LENGTH('dbo.promotions', 'description') IS NULL
    ALTER TABLE [dbo].[promotions] ADD description NVARCHAR(500) NULL;
GO

IF OBJECT_ID(N'dbo.businessInfo', N'U') IS NULL
CREATE TABLE [dbo].[businessInfo] (
    businessInfoId INT IDENTITY(1,1) NOT NULL,
    companyId      INT            NOT NULL,
    branchId       INT            NULL,
    address        NVARCHAR(300)  NULL,
    mapsUrl        NVARCHAR(500)  NULL,
    phone          NVARCHAR(30)   NULL,
    email          NVARCHAR(120)  NULL,
    paymentMethods NVARCHAR(300)  NULL,   -- "Efectivo, tarjeta, transferencia"
    servicesInfo   NVARCHAR(2000) NULL,   -- prices / what's included, free text
    extraInfo      NVARCHAR(2000) NULL,   -- anything else the agent may say
    createdAt      DATETIME2      NOT NULL CONSTRAINT DF_businessInfo_createdAt DEFAULT (GETUTCDATE()),
    updatedAt      DATETIME2      NULL,
    CONSTRAINT PK_businessInfo PRIMARY KEY CLUSTERED (businessInfoId)
);
GO
-- One company-wide row and at most one row per branch.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_businessInfo_company_branch')
    CREATE UNIQUE INDEX UQ_businessInfo_company_branch
        ON [dbo].[businessInfo] (companyId, branchId);
GO

IF OBJECT_ID(N'dbo.businessFaqs', N'U') IS NULL
CREATE TABLE [dbo].[businessFaqs] (
    faqId      INT IDENTITY(1,1) NOT NULL,
    companyId  INT            NOT NULL,
    branchId   INT            NULL,
    question   NVARCHAR(300)  NOT NULL,
    answer     NVARCHAR(1500) NOT NULL,
    sortOrder  INT            NOT NULL CONSTRAINT DF_businessFaqs_sortOrder DEFAULT (0),
    isActive   BIT            NOT NULL CONSTRAINT DF_businessFaqs_isActive DEFAULT (1),
    createdAt  DATETIME2      NOT NULL CONSTRAINT DF_businessFaqs_createdAt DEFAULT (GETUTCDATE()),
    updatedAt  DATETIME2      NULL,
    CONSTRAINT PK_businessFaqs PRIMARY KEY CLUSTERED (faqId)
);
GO
