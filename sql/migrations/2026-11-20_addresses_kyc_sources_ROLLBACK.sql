-- ============================================================================
-- ROLLBACK of 2026-11-20_addresses_kyc_sources.sql + sql/sp_addresses.sql.
-- Returns dbo.addresses to its 2024 shape (addressId, street, postalCode, city,
-- state, createdAt, updatedAt). DESTRUCTIVE: the ine/gps address rows lose
-- their client, source, full address and coordinates. Export them first if
-- they matter:  SELECT * FROM dbo.addresses;
-- Run by hand in SSMS. Idempotent.
-- ============================================================================

DROP PROCEDURE IF EXISTS dbo.sp_addresses;
DROP PROCEDURE IF EXISTS dbo.sp_addresses_all;
DROP PROCEDURE IF EXISTS dbo.sp_addresses_one;
GO

DROP INDEX IF EXISTS UQ_addresses_company_client_source_active ON dbo.addresses;
ALTER TABLE dbo.addresses DROP CONSTRAINT IF EXISTS FK_addresses_clientFaceRecognitions;
ALTER TABLE dbo.addresses DROP CONSTRAINT IF EXISTS FK_addresses_clients;
ALTER TABLE dbo.addresses DROP CONSTRAINT IF EXISTS FK_addresses_companies;
ALTER TABLE dbo.addresses DROP CONSTRAINT IF EXISTS CK_addresses_source;
ALTER TABLE dbo.addresses DROP CONSTRAINT IF EXISTS DF_addresses_isActive;
GO

ALTER TABLE dbo.addresses DROP COLUMN IF EXISTS isActive;
ALTER TABLE dbo.addresses DROP COLUMN IF EXISTS accuracyMeters;
ALTER TABLE dbo.addresses DROP COLUMN IF EXISTS longitude;
ALTER TABLE dbo.addresses DROP COLUMN IF EXISTS latitude;
ALTER TABLE dbo.addresses DROP COLUMN IF EXISTS fullAddress;
ALTER TABLE dbo.addresses DROP COLUMN IF EXISTS source;
ALTER TABLE dbo.addresses DROP COLUMN IF EXISTS clientFaceRecognitionId;
ALTER TABLE dbo.addresses DROP COLUMN IF EXISTS clientId;
ALTER TABLE dbo.addresses DROP COLUMN IF EXISTS companyId;
GO
