-- =============================================================================
-- dbo.demandSignals — interés por servicio y zona (Client Acquisition: validación
-- de ubicaciones)
-- =============================================================================
-- WHY: decidir dónde poner lockers / autoservicio 24 h con demanda comprobable.
--      Cada persona (teléfono) interesada en un concepto es UNA fila, que el
--      agente de WhatsApp va completando durante la conversación.
-- WHAT: generado por posgmo-factory (PRD tests/prd_demandSignal.json, 2026-11-10)
--       y corregido a mano: listas de valores del PRD, DATETIME2, sin borrado.
-- Writer: modules/whatsappReservations (RECORD_DEMAND_SIGNAL) → sp_demandSignals
-- Readers: POST /all_demandSignals, /one_demandSignals, /demandSignals/zoneSummary
-- Run order: this file → sp_demandSignals.sql → _all.sql → _one.sql
--            → _zoneSummary.sql → deploy the backend.
-- Zonas solo a nivel colonia (centroide), nunca una dirección.
-- Safe to re-run. ROLLBACK: 2026-11-10_demandSignals_ROLLBACK.sql
-- =============================================================================

IF OBJECT_ID(N'dbo.demandSignals', N'U') IS NULL
CREATE TABLE [dbo].[demandSignals] (
    demandSignalId             INT IDENTITY(1,1) NOT NULL,
    companyId                  INT NOT NULL,
    channelId                  INT NOT NULL,
    customerPhone              NVARCHAR(20) NOT NULL,
    clientId                   INT NULL,
    marketingLeadAttributionId INT NULL,
    concept                    NVARCHAR(30) NOT NULL
        CONSTRAINT CK_demandSignals_concept CHECK (concept IN ('autoservicio_24h', 'lockers', 'qr_gmo')),
    origin                     NVARCHAR(20) NOT NULL
        CONSTRAINT CK_demandSignals_origin CHECK (origin IN ('anuncio', 'organico', 'personal')),
    residenceZoneText          NVARCHAR(120) NULL,
    workZoneText               NVARCHAR(120) NULL,
    preferredZoneText          NVARCHAR(120) NOT NULL,
    preferredZoneName          NVARCHAR(120) NULL,
    preferredZoneLat           DECIMAL(9,6) NULL,
    preferredZoneLng           DECIMAL(9,6) NULL,
    frequency                  NVARCHAR(20) NULL
        CONSTRAINT CK_demandSignals_frequency CHECK (frequency IN ('semanal', 'quincenal', 'mensual', 'ocasional')),
    preferredTime              NVARCHAR(20) NULL
        CONSTRAINT CK_demandSignals_preferredTime CHECK (preferredTime IN ('temprano', 'dia', 'tarde', 'noche', 'madrugada', 'fin_de_semana')),
    currentSolution            NVARCHAR(20) NULL
        CONSTRAINT CK_demandSignals_currentSolution CHECK (currentSolution IN ('lavadora_propia', 'lavanderia', 'familiar', 'otro')),
    painPoint                  NVARCHAR(200) NULL,
    wouldUse                   NVARCHAR(10) NULL
        CONSTRAINT CK_demandSignals_wouldUse CHECK (wouldUse IN ('si', 'tal_vez', 'no')),
    notifyOptIn                BIT NOT NULL CONSTRAINT DF_demandSignals_notifyOptIn DEFAULT (0),
    optInAt                    DATETIME2 NULL,
    intentLevel                NVARCHAR(10) NOT NULL
        CONSTRAINT CK_demandSignals_intentLevel CHECK (intentLevel IN ('alta', 'media', 'baja')),
    created_at                 DATETIME2 NOT NULL CONSTRAINT DF_demandSignals_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at                 DATETIME2 NOT NULL CONSTRAINT DF_demandSignals_updated_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_demandSignals PRIMARY KEY CLUSTERED (demandSignalId),
    CONSTRAINT FK_demandSignals_companies FOREIGN KEY (companyId) REFERENCES dbo.companies(companyId),
    CONSTRAINT FK_demandSignals_whatsappChannels FOREIGN KEY (channelId) REFERENCES dbo.whatsappChannels(channelId),
    CONSTRAINT FK_demandSignals_clients FOREIGN KEY (clientId) REFERENCES dbo.clients(clientId),
    CONSTRAINT FK_demandSignals_marketingLeadAttributions FOREIGN KEY (marketingLeadAttributionId)
        REFERENCES dbo.marketingLeadAttributions(marketingLeadAttributionId),
    CONSTRAINT UQ_demandSignals_company_phone_concept UNIQUE NONCLUSTERED (companyId, customerPhone, concept)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_demandSignals_company_created' AND object_id = OBJECT_ID('dbo.demandSignals'))
    CREATE NONCLUSTERED INDEX IX_demandSignals_company_created ON dbo.demandSignals (companyId, created_at);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_demandSignals_company_concept_zone' AND object_id = OBJECT_ID('dbo.demandSignals'))
    CREATE NONCLUSTERED INDEX IX_demandSignals_company_concept_zone ON dbo.demandSignals (companyId, concept, preferredZoneName);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_demandSignals_company_attribution' AND object_id = OBJECT_ID('dbo.demandSignals'))
    CREATE NONCLUSTERED INDEX IX_demandSignals_company_attribution ON dbo.demandSignals (companyId, marketingLeadAttributionId);
GO
