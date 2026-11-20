-- ============================================================================
-- dbo.bankAccounts.verificationAttempts — wrong micro-deposit guesses so far.
--
-- Why: /bank-account/verify compared the centavos with no limit. With only 99
-- possible values anyone could verify any CLABE in <= 99 calls. The count now
-- lives on the row and sp_bankAccounts action 4 compares + counts in one
-- transaction; at MICRODEPOSIT_MAX_ATTEMPTS (default 3) the account is locked
-- and even the right amount is refused. RFC-018 §3.3 (POSVending docs/rfcs),
-- rollout step 1 — independent of STP.
--
-- Written by:  sp_bankAccounts action 4 (attempt) <- modules/bankAccounts.py
--              verify_bank_account <- POST /bank-account/verify.
--              sp_bankAccounts action 2 with verificationAttempts = 0 resets
--              it (support unlock).
-- Read by:     sp_bankAccounts action 4, sp_bankAccounts_all (UI shows the
--              lock / attempts left after a reload).
--
-- Run order (SSMS / Azure Data Studio, DEV -> QA -> PROD):
--   1. this file
--   2. sql/sp_bankAccounts.sql   (NOTE: that file also carries the RFC-017
--      changes — check they are approved for the target DB before running it)
-- The backend refuses verification (fail closed, HTTP 503) until step 2 has run.
-- BEFORE APPLYING: the local .env may point at the PRODUCTION database — check
-- the backend startup banner ([appEnv][startup] ... DB=...).
-- Idempotent (re-runnable). Rollback: 2026-11-20_bankAccounts_verification_attempts_ROLLBACK.sql
-- ============================================================================

IF COL_LENGTH('dbo.bankAccounts', 'verificationAttempts') IS NULL
    ALTER TABLE dbo.bankAccounts
        ADD verificationAttempts INT NOT NULL
            CONSTRAINT DF_bankAccounts_verificationAttempts DEFAULT 0;
GO
