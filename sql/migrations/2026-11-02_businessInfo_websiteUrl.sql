-- =============================================================================
-- dbo.businessInfo.websiteUrl — the business's website
-- =============================================================================
-- WHY: the WhatsApp assistant has no link to send when a customer asks for the
--      website (Lavandería: https://www.gmolavanderia.com/home).
-- WHAT: one NULL column. A branch row that leaves it empty falls back to the
--       company-wide row (branchId NULL) in sp_businessInfo, like the others.
-- Readers/writers: sql/sp_businessInfo.sql (POST /businessInfo, actions 0 and 1).
-- Run order: after 2026-11-01_businessInfo_pickup_delivery_address.sql;
--            this file → sql/sp_businessInfo.sql (it references the column).
-- Safe to re-run. ROLLBACK: 2026-11-02_businessInfo_websiteUrl_ROLLBACK.sql
-- =============================================================================

IF COL_LENGTH('dbo.businessInfo', 'websiteUrl') IS NULL
    ALTER TABLE [dbo].[businessInfo] ADD websiteUrl NVARCHAR(500) NULL;
GO
