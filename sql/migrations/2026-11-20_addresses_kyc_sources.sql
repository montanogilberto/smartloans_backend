-- ============================================================================
-- dbo.addresses — one row per address SOURCE of a client (ine / gps).
--
-- Why: the SmartLoans KYC wizard reads Domicilio off the INE, then
-- reverse-geocodes the presence-capture GPS. The GPS address used to
-- OVERWRITE the INE one (different street spelling, no house number). Both are
-- evidence and are now kept side by side:
--   source 'ine' — the address as printed on the INE (or as the person
--                  corrected it on the "Tus datos" step); the one that goes into
--                  the contract / pagaré (clientFaceRecognitions.domicilio).
--   source 'gps' — reverse-geocoded from the presence capture, with the
--                  coordinates and accuracy it came from.
-- One ACTIVE row per (companyId, clientId, source): a new KYC capture updates
-- that row instead of adding another.
--
-- Reuses the existing, unused dbo.addresses (created 2024, 0 rows, nothing
-- references it). Its columns addressId, street, postalCode, city, state,
-- createdAt, updatedAt are kept as they are (createdAt/updatedAt predate the
-- created_At/updated_at convention; renaming them buys nothing).
--
-- Written by:  sp_addresses (sql/sp_addresses.sql) <- modules/addresses.py
--              <- POST /addresses <- smartLoans src/api/addressesApi.ts
--              (ClientFaceRecognitionPage: gps row at the presence capture,
--               ine row when the contract is submitted).
-- Read by:     sp_addresses_all / sp_addresses_one <- POST /addresses/client,
--              POST /addresses/one.
--
-- Run order (SSMS / Azure Data Studio, DEV -> QA -> PROD):
--   1. this file
--   2. sql/sp_addresses.sql
-- BEFORE APPLYING: the local .env may point at the PRODUCTION database — check
-- the backend startup banner ([appEnv][startup] ... DB=...).
-- Idempotent (re-runnable). Rollback: 2026-11-20_addresses_kyc_sources_ROLLBACK.sql
-- Addresses are personal data: never logged, never in URLs.
-- ============================================================================

IF COL_LENGTH('dbo.addresses', 'companyId') IS NULL
    ALTER TABLE dbo.addresses ADD companyId INT NULL;
IF COL_LENGTH('dbo.addresses', 'clientId') IS NULL
    ALTER TABLE dbo.addresses ADD clientId INT NULL;
IF COL_LENGTH('dbo.addresses', 'clientFaceRecognitionId') IS NULL
    ALTER TABLE dbo.addresses ADD clientFaceRecognitionId INT NULL;
IF COL_LENGTH('dbo.addresses', 'source') IS NULL
    ALTER TABLE dbo.addresses ADD source NVARCHAR(20) NULL;
IF COL_LENGTH('dbo.addresses', 'fullAddress') IS NULL
    ALTER TABLE dbo.addresses ADD fullAddress NVARCHAR(500) NULL;
IF COL_LENGTH('dbo.addresses', 'latitude') IS NULL
    ALTER TABLE dbo.addresses ADD latitude DECIMAL(9,6) NULL;
IF COL_LENGTH('dbo.addresses', 'longitude') IS NULL
    ALTER TABLE dbo.addresses ADD longitude DECIMAL(9,6) NULL;
IF COL_LENGTH('dbo.addresses', 'accuracyMeters') IS NULL
    ALTER TABLE dbo.addresses ADD accuracyMeters DECIMAL(9,2) NULL;
IF COL_LENGTH('dbo.addresses', 'isActive') IS NULL
    ALTER TABLE dbo.addresses ADD isActive BIT NOT NULL
        CONSTRAINT DF_addresses_isActive DEFAULT 1;
GO

-- The table had no rows, so the identifying columns can be NOT NULL. Guarded:
-- skipped (left NULL-able) if rows without them ever exist.
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.addresses') AND name = 'companyId' AND is_nullable = 1)
   AND NOT EXISTS (SELECT 1 FROM dbo.addresses WHERE companyId IS NULL)
    ALTER TABLE dbo.addresses ALTER COLUMN companyId INT NOT NULL;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.addresses') AND name = 'clientId' AND is_nullable = 1)
   AND NOT EXISTS (SELECT 1 FROM dbo.addresses WHERE clientId IS NULL)
    ALTER TABLE dbo.addresses ALTER COLUMN clientId INT NOT NULL;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.addresses') AND name = 'source' AND is_nullable = 1)
   AND NOT EXISTS (SELECT 1 FROM dbo.addresses WHERE source IS NULL)
    ALTER TABLE dbo.addresses ALTER COLUMN source NVARCHAR(20) NOT NULL;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.addresses') AND name = 'fullAddress' AND is_nullable = 1)
   AND NOT EXISTS (SELECT 1 FROM dbo.addresses WHERE fullAddress IS NULL)
    ALTER TABLE dbo.addresses ALTER COLUMN fullAddress NVARCHAR(500) NOT NULL;
GO

IF OBJECT_ID('dbo.CK_addresses_source', 'C') IS NULL
    ALTER TABLE dbo.addresses ADD CONSTRAINT CK_addresses_source CHECK (source IN ('ine', 'gps'));
IF OBJECT_ID('dbo.FK_addresses_companies', 'F') IS NULL
    ALTER TABLE dbo.addresses ADD CONSTRAINT FK_addresses_companies
        FOREIGN KEY (companyId) REFERENCES dbo.companies (companyId);
IF OBJECT_ID('dbo.FK_addresses_clients', 'F') IS NULL
    ALTER TABLE dbo.addresses ADD CONSTRAINT FK_addresses_clients
        FOREIGN KEY (clientId) REFERENCES dbo.clients (clientId);
IF OBJECT_ID('dbo.FK_addresses_clientFaceRecognitions', 'F') IS NULL
    ALTER TABLE dbo.addresses ADD CONSTRAINT FK_addresses_clientFaceRecognitions
        FOREIGN KEY (clientFaceRecognitionId) REFERENCES dbo.clientFaceRecognitions (clientFaceRecognitionId);
GO

-- One active row per client and source; also serves the per-client read.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.addresses')
               AND name = 'UQ_addresses_company_client_source_active')
    CREATE UNIQUE NONCLUSTERED INDEX UQ_addresses_company_client_source_active
        ON dbo.addresses (companyId, clientId, source)
        WHERE isActive = 1;
GO
