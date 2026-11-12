-- =============================================================================
-- 2026-11-12 — dbo.demandSignals.prospectName
-- =============================================================================
-- The prospect's name as they gave it on WhatsApp (optional; asked once by the
-- agent). Phone and zone already exist. Idempotent: safe to run twice.
-- Run BEFORE deploying the new sp_demandSignals / sp_demandSignals_all.
-- =============================================================================
IF COL_LENGTH('dbo.demandSignals', 'prospectName') IS NULL
    ALTER TABLE dbo.demandSignals ADD prospectName NVARCHAR(120) NULL;
GO
