-- =============================================================================
-- 2026-11-12 — dbo.demandSignals.preferredZoneText becomes optional
-- =============================================================================
-- Every possible new client from the campaign is stored as soon as we know which
-- service they're interested in, even if they leave before naming a zone. Rows
-- without a zone show as 'sin ubicar' in sp_demandSignals_zoneSummary (it groups
-- by preferredZoneName, already NULL for them). Idempotent: safe to run twice.
-- Run BEFORE deploying the new sp_demandSignals.
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('dbo.demandSignals') AND name = 'preferredZoneText' AND is_nullable = 0)
    ALTER TABLE dbo.demandSignals ALTER COLUMN preferredZoneText NVARCHAR(120) NULL;
GO
