-- =============================================================================
-- ROLLBACK of 2026-11-01_businessInfo_pickup_delivery_address.sql
-- =============================================================================
-- Run order: first redeploy the previous sql/sp_businessInfo.sql (git history,
-- before 2026-11-01) — the current one references these columns — then this file.
-- Drops the six columns and their data. Safe to re-run.
-- =============================================================================

IF COL_LENGTH('dbo.businessInfo', 'pickupPolicy') IS NOT NULL
    ALTER TABLE [dbo].[businessInfo] DROP COLUMN pickupPolicy;
GO
IF COL_LENGTH('dbo.businessInfo', 'deliveryPolicy') IS NOT NULL
    ALTER TABLE [dbo].[businessInfo] DROP COLUMN deliveryPolicy;
GO
IF COL_LENGTH('dbo.businessInfo', 'whatsappNumber') IS NOT NULL
    ALTER TABLE [dbo].[businessInfo] DROP COLUMN whatsappNumber;
GO
IF COL_LENGTH('dbo.businessInfo', 'street') IS NOT NULL
    ALTER TABLE [dbo].[businessInfo] DROP COLUMN street;
GO
IF COL_LENGTH('dbo.businessInfo', 'city') IS NOT NULL
    ALTER TABLE [dbo].[businessInfo] DROP COLUMN city;
GO
IF COL_LENGTH('dbo.businessInfo', 'postalCode') IS NOT NULL
    ALTER TABLE [dbo].[businessInfo] DROP COLUMN postalCode;
GO
