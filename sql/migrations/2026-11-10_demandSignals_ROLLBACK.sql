-- =============================================================================
-- ROLLBACK of 2026-11-10_demandSignals.sql
-- =============================================================================
-- Run order: first deploy a backend without RECORD_DEMAND_SIGNAL, then this file.
-- Drops the SPs, the table and ALL recorded demand signals. Safe to re-run.
-- =============================================================================

DROP PROCEDURE IF EXISTS [dbo].[sp_demandSignals_zoneSummary];
DROP PROCEDURE IF EXISTS [dbo].[sp_demandSignals_one];
DROP PROCEDURE IF EXISTS [dbo].[sp_demandSignals_all];
DROP PROCEDURE IF EXISTS [dbo].[sp_demandSignals];
DROP TABLE IF EXISTS [dbo].[demandSignals];
GO
