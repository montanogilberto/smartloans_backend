-- =============================================================================
-- Add consentAccepted / consentAcceptedAt to dbo.loanOffers
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB, then re-run
-- sql/sp_loanOffers.sql to update the stored procedures.
--
-- WHY: "Publicar capital disponible" gates the submit button on a checkbox
-- ("Declaro que el capital indicado está disponible..."), but the agreement
-- itself was never persisted anywhere — only enforced client-side. This adds
-- a durable, per-offer audit record of that consent.
--
-- SCOPE: adds exactly 2 nullable/defaulted columns to the existing
-- dbo.loanOffers table. Does not touch any other table, does not rewrite
-- existing rows (they get consentAccepted=0/consentAcceptedAt=NULL, which is
-- honest — they predate this feature and never captured explicit consent).
-- Idempotent: guarded by sys.columns existence checks, safe to run more than
-- once.
-- =============================================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.loanOffers') AND name = 'consentAccepted'
)
BEGIN
    ALTER TABLE [dbo].[loanOffers] ADD consentAccepted BIT NOT NULL DEFAULT 0;
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.loanOffers') AND name = 'consentAcceptedAt'
)
BEGIN
    -- DATETIME (not DATETIME2) to match every other timestamp column already
    -- in this table (sp_loanOffers.sql's own comment: factory reviewer_agent
    -- auto-errors DATETIME2 outside IOT modules).
    ALTER TABLE [dbo].[loanOffers] ADD consentAcceptedAt DATETIME NULL;
END
GO
