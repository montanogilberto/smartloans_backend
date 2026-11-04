-- =============================================================================
-- dbo.marketingLeadAttributions — which ad brought each lead (Client Acquisition)
-- =============================================================================
-- WHY: Meta sends the ad's data (messages[].referral) only on the first WhatsApp
--      message after a Click-to-WhatsApp ad, and it can't be recovered later. It
--      must be saved before any ad money is spent.
-- WHAT: one immutable row per ad-originated message. The WhatsApp channel sets
--       companyId; the referral sets the attribution.
-- Writer: modules/whatsappCloud._record_ad_referral → sql/sp_marketingLeadAttributions.sql
-- Readers: POST /all_marketingLeadAttributions, /one_marketingLeadAttributions
-- Run order: this file → sp_marketingLeadAttributions.sql → _all.sql → _one.sql
--            → deploy the backend (the webhook calls the SP).
-- Safe to re-run. ROLLBACK: 2026-11-04_marketingLeadAttributions_ROLLBACK.sql
-- =============================================================================

IF OBJECT_ID(N'dbo.marketingLeadAttributions', N'U') IS NULL
CREATE TABLE [dbo].[marketingLeadAttributions] (
    marketingLeadAttributionId INT IDENTITY(1,1) NOT NULL,
    companyId INT NOT NULL,
    provider NVARCHAR(20) NOT NULL,
    conversionChannel NVARCHAR(20) NOT NULL,
    channelId INT NULL,
    customerPhone NVARCHAR(20) NOT NULL,
    clientId INT NULL,
    isNewLead BIT NOT NULL,
    externalEventId NVARCHAR(128) NOT NULL,
    sourceType NVARCHAR(20) NULL,
    sourceId NVARCHAR(64) NULL,
    ctwaClid NVARCHAR(512) NULL,
    headline NVARCHAR(255) NULL,
    body NVARCHAR(1000) NULL,
    sourceUrl NVARCHAR(500) NULL,
    mediaType NVARCHAR(20) NULL,
    rawReferral NVARCHAR(MAX) NULL,
    referredAt DATETIME2 NOT NULL,
    created_At DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    updated_at DATETIME2 NULL,
    CONSTRAINT PK_marketingLeadAttributions PRIMARY KEY CLUSTERED (marketingLeadAttributionId),
    CONSTRAINT FK_marketingLeadAttributions_companies FOREIGN KEY (companyId) REFERENCES dbo.companies(companyId),
    CONSTRAINT FK_marketingLeadAttributions_whatsappChannels FOREIGN KEY (channelId) REFERENCES dbo.whatsappChannels(channelId),
    CONSTRAINT FK_marketingLeadAttributions_clients FOREIGN KEY (clientId) REFERENCES dbo.clients(clientId),
    CONSTRAINT UQ_marketingLeadAttributions_CompanyProviderExternalEvent UNIQUE NONCLUSTERED (companyId, provider, externalEventId),
    CONSTRAINT CK_marketingLeadAttributions_Provider CHECK (provider IN ('meta')),
    CONSTRAINT CK_marketingLeadAttributions_ConversionChannel CHECK (conversionChannel IN ('whatsapp')),
    CONSTRAINT CK_marketingLeadAttributions_ConversionChannel_ChannelId CHECK (conversionChannel <> 'whatsapp' OR channelId IS NOT NULL),
    CONSTRAINT CK_marketingLeadAttributions_RawReferral_IsJson CHECK (rawReferral IS NULL OR ISJSON(rawReferral) = 1)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_marketingLeadAttributions_channelId' AND object_id = OBJECT_ID(N'dbo.marketingLeadAttributions'))
    CREATE NONCLUSTERED INDEX IX_marketingLeadAttributions_channelId ON dbo.marketingLeadAttributions (channelId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_marketingLeadAttributions_clientId' AND object_id = OBJECT_ID(N'dbo.marketingLeadAttributions'))
    CREATE NONCLUSTERED INDEX IX_marketingLeadAttributions_clientId ON dbo.marketingLeadAttributions (clientId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_marketingLeadAttributions_CompanyReferredAt' AND object_id = OBJECT_ID(N'dbo.marketingLeadAttributions'))
    CREATE NONCLUSTERED INDEX IX_marketingLeadAttributions_CompanyReferredAt ON dbo.marketingLeadAttributions (companyId, referredAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_marketingLeadAttributions_CompanySourceIdReferredAt' AND object_id = OBJECT_ID(N'dbo.marketingLeadAttributions'))
    CREATE NONCLUSTERED INDEX IX_marketingLeadAttributions_CompanySourceIdReferredAt ON dbo.marketingLeadAttributions (companyId, sourceId, referredAt DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_marketingLeadAttributions_CompanyCustomerPhone' AND object_id = OBJECT_ID(N'dbo.marketingLeadAttributions'))
    CREATE NONCLUSTERED INDEX IX_marketingLeadAttributions_CompanyCustomerPhone ON dbo.marketingLeadAttributions (companyId, customerPhone);
GO
