-- ============================================================================
-- ROLLBACK of 2026-11-20_bankAccounts_verification_attempts.sql.
-- Run sql/sp_bankAccounts.sql from the commit BEFORE this change FIRST (the
-- current version references the column and would fail at runtime), then this.
-- Drops the counter: pending accounts go back to unlimited guesses.
-- Run by hand in SSMS. Idempotent.
-- ============================================================================

ALTER TABLE dbo.bankAccounts DROP CONSTRAINT IF EXISTS DF_bankAccounts_verificationAttempts;
GO
ALTER TABLE dbo.bankAccounts DROP COLUMN IF EXISTS verificationAttempts;
GO
