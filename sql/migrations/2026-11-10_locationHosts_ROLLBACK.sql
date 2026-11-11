-- =============================================================================
-- ROLLBACK of 2026-11-10_locationHosts.sql
-- =============================================================================
-- Run order: first deploy a backend without RECORD_LOCATION_HOST, then this file.
-- Drops the SPs, the table and ALL host candidates. Safe to re-run.
-- =============================================================================

DROP PROCEDURE IF EXISTS [dbo].[sp_locationHosts_status];
DROP PROCEDURE IF EXISTS [dbo].[sp_locationHosts_all];
DROP PROCEDURE IF EXISTS [dbo].[sp_locationHosts];
DROP TABLE IF EXISTS [dbo].[locationHosts];
GO
