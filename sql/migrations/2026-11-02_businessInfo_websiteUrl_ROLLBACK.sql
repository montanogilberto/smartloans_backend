-- =============================================================================
-- ROLLBACK of 2026-11-02_businessInfo_websiteUrl.sql
-- =============================================================================
-- Run order: first redeploy the previous sql/sp_businessInfo.sql (git history,
-- before 2026-11-02) — the current one references this column — then this file.
-- Drops the column and its data. Safe to re-run.
-- =============================================================================

IF COL_LENGTH('dbo.businessInfo', 'websiteUrl') IS NOT NULL
    ALTER TABLE [dbo].[businessInfo] DROP COLUMN websiteUrl;
GO
