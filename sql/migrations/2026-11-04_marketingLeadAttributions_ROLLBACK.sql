-- =============================================================================
-- ROLLBACK of 2026-11-04_marketingLeadAttributions.sql
-- =============================================================================
-- Run order: first deploy a backend without _record_ad_referral, then this file.
-- Drops the SPs, the table and ALL recorded ad clicks, which can't be recovered.
-- Safe to re-run.
-- =============================================================================

DROP PROCEDURE IF EXISTS [dbo].[sp_marketingLeadAttributions_one];
DROP PROCEDURE IF EXISTS [dbo].[sp_marketingLeadAttributions_all];
DROP PROCEDURE IF EXISTS [dbo].[sp_marketingLeadAttributions];
DROP TABLE IF EXISTS [dbo].[marketingLeadAttributions];
GO
