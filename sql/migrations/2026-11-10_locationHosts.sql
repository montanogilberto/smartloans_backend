-- =============================================================================
-- dbo.locationHosts — Red GMO: negocios que ofrecen espacio para un locker GMO
-- =============================================================================
-- WHY: elegir dónde instalar lockers cruzando la demanda (dbo.demandSignals) con
--      los negocios dispuestos a prestar espacio. GMO opera el locker; la comisión
--      del socio y su pago semanal NO están aquí (necesitan un RFC de pagos).
-- WHAT: PRD posgmo-factory tests/prd_locationHost.json (2026-11-10). El factory no
--       pasó la validación del SQL; este archivo está escrito a mano con sus listas
--       de valores y el patrón de demandSignals.
-- Writer: modules/whatsappReservations (RECORD_LOCATION_HOST) → sp_locationHosts
--         staff: POST /locationHosts/status → sp_locationHosts_status
-- Readers: POST /all_locationHosts
-- Run order: this file → sp_locationHosts.sql → _all.sql → _status.sql → deploy.
-- Safe to re-run. ROLLBACK: 2026-11-10_locationHosts_ROLLBACK.sql
-- =============================================================================

IF OBJECT_ID(N'dbo.locationHosts', N'U') IS NULL
CREATE TABLE [dbo].[locationHosts] (
    locationHostId             INT IDENTITY(1,1) NOT NULL,
    companyId                  INT NOT NULL,
    channelId                  INT NOT NULL,
    contactPhone               NVARCHAR(20) NOT NULL,
    marketingLeadAttributionId INT NULL,
    origin                     NVARCHAR(20) NOT NULL
        CONSTRAINT CK_locationHosts_origin CHECK (origin IN ('anuncio', 'organico', 'personal')),
    businessName               NVARCHAR(120) NOT NULL,
    businessType               NVARCHAR(20) NULL
        CONSTRAINT CK_locationHosts_businessType CHECK (businessType IN
            ('tienda', 'gimnasio', 'farmacia', 'oficina', 'escuela', 'gasolinera', 'restaurante', 'otro')),
    contactName                NVARCHAR(120) NULL,
    contactRole                NVARCHAR(20) NULL
        CONSTRAINT CK_locationHosts_contactRole CHECK (contactRole IN ('dueno', 'encargado', 'otro')),
    zoneText                   NVARCHAR(120) NOT NULL,
    addressText                NVARCHAR(200) NULL,
    zoneName                   NVARCHAR(120) NULL,
    zoneLat                    DECIMAL(9,6) NULL,
    zoneLng                    DECIMAL(9,6) NULL,
    openingHours               NVARCHAR(120) NULL,
    opensWeekends              BIT NULL,
    spaceType                  NVARCHAR(20) NULL
        CONSTRAINT CK_locationHosts_spaceType CHECK (spaceType IN ('interior', 'exterior', 'estacionamiento', 'no_seguro')),
    dailyVisitors              NVARCHAR(20) NULL
        CONSTRAINT CK_locationHosts_dailyVisitors CHECK (dailyVisitors IN ('menos_50', '50_200', 'mas_200', 'no_seguro')),
    hasParking                 BIT NULL,
    contactOptIn               BIT NOT NULL CONSTRAINT DF_locationHosts_contactOptIn DEFAULT (0),
    optInAt                    DATETIME2 NULL,
    status                     NVARCHAR(20) NOT NULL CONSTRAINT DF_locationHosts_status DEFAULT ('nuevo')
        CONSTRAINT CK_locationHosts_status CHECK (status IN
            ('nuevo', 'contactado', 'visitado', 'aprobado', 'instalado', 'descartado')),
    staffNotes                 NVARCHAR(500) NULL,
    created_at                 DATETIME2 NOT NULL CONSTRAINT DF_locationHosts_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at                 DATETIME2 NOT NULL CONSTRAINT DF_locationHosts_updated_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_locationHosts PRIMARY KEY CLUSTERED (locationHostId),
    CONSTRAINT FK_locationHosts_companies FOREIGN KEY (companyId) REFERENCES dbo.companies(companyId),
    CONSTRAINT FK_locationHosts_whatsappChannels FOREIGN KEY (channelId) REFERENCES dbo.whatsappChannels(channelId),
    CONSTRAINT FK_locationHosts_marketingLeadAttributions FOREIGN KEY (marketingLeadAttributionId)
        REFERENCES dbo.marketingLeadAttributions(marketingLeadAttributionId),
    CONSTRAINT UQ_locationHosts_company_phone_business UNIQUE NONCLUSTERED (companyId, contactPhone, businessName)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_locationHosts_company_created' AND object_id = OBJECT_ID('dbo.locationHosts'))
    CREATE NONCLUSTERED INDEX IX_locationHosts_company_created ON dbo.locationHosts (companyId, created_at);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_locationHosts_company_status' AND object_id = OBJECT_ID('dbo.locationHosts'))
    CREATE NONCLUSTERED INDEX IX_locationHosts_company_status ON dbo.locationHosts (companyId, status);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_locationHosts_company_zone' AND object_id = OBJECT_ID('dbo.locationHosts'))
    CREATE NONCLUSTERED INDEX IX_locationHosts_company_zone ON dbo.locationHosts (companyId, zoneName);
GO
