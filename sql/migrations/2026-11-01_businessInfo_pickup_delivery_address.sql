-- =============================================================================
-- dbo.businessInfo: pickup / delivery policy, WhatsApp number, structured address
-- =============================================================================
-- WHY: the WhatsApp assistant answered "can I send an Uber for my laundry?" from
--      free text and gave a placeholder address. It needs the pickup and delivery
--      rules and the address as separate fields it can quote as-is.
-- WHAT: six NULL columns. Like the existing ones, a branch row that leaves a field
--       empty falls back to the company-wide row (branchId NULL) in sp_businessInfo.
--         pickupPolicy    who can pick up an order, by courier/Uber or not, …
--         deliveryPolicy  whether the business delivers, zones, cost, schedule
--         whatsappNumber  the number customers write to (display, e.g. +52 662 …)
--         street / city / postalCode  structured address; `address` stays as
--                         the one-line text the assistant already reads.
-- Readers/writers: sql/sp_businessInfo.sql (POST /businessInfo, actions 0 and 1),
--                  read by the WhatsApp assistant and the POS.
-- Run order: this file → sql/sp_businessInfo.sql (it references the columns).
-- Safe to re-run. ROLLBACK: 2026-11-01_businessInfo_pickup_delivery_address_ROLLBACK.sql
-- =============================================================================

IF COL_LENGTH('dbo.businessInfo', 'pickupPolicy') IS NULL
    ALTER TABLE [dbo].[businessInfo] ADD pickupPolicy NVARCHAR(1000) NULL;
GO
IF COL_LENGTH('dbo.businessInfo', 'deliveryPolicy') IS NULL
    ALTER TABLE [dbo].[businessInfo] ADD deliveryPolicy NVARCHAR(1000) NULL;
GO
IF COL_LENGTH('dbo.businessInfo', 'whatsappNumber') IS NULL
    ALTER TABLE [dbo].[businessInfo] ADD whatsappNumber NVARCHAR(30) NULL;
GO
IF COL_LENGTH('dbo.businessInfo', 'street') IS NULL
    ALTER TABLE [dbo].[businessInfo] ADD street NVARCHAR(300) NULL;
GO
IF COL_LENGTH('dbo.businessInfo', 'city') IS NULL
    ALTER TABLE [dbo].[businessInfo] ADD city NVARCHAR(120) NULL;
GO
IF COL_LENGTH('dbo.businessInfo', 'postalCode') IS NULL
    ALTER TABLE [dbo].[businessInfo] ADD postalCode NVARCHAR(10) NULL;
GO
