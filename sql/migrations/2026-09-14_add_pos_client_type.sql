-- =============================================================================
-- Add 'pos' as a valid dbo.clients.clientType value
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- run manually against smartloansbackend's live DB.
--
-- WHY: clientType's CHECK constraint (CK_clients_clientType) only ever
-- allowed 'borrower' | 'lender' | 'both' | 'lawyer' — all four are
-- SmartLoans lending roles. There was no honest value for a plain POS
-- retail customer with no lending relationship at all; the wizard's
-- default silently labeled them 'borrower' (loan applicant), which is
-- semantically wrong even though it doesn't break anything functional
-- (reward points are NOT gated by clientType — see sql/sp_rewardBenefits.sql
-- / modules/rewardBenefits.py, neither references this column — so this
-- migration is purely a correctness fix for how the client is labeled and
-- displayed, not a prerequisite for rewards to work).
--
-- Confirmed via live query before writing this: today's real data is 122
-- 'borrower', 2 'both', 2 'lender', 0 'lawyer', 0 anything else — every
-- client in this table so far has been a lending participant.
--
-- Uses lowercase 'pos' to match the existing all-lowercase convention
-- (borrower/lender/both/lawyer), not the uppercase 'POS' first suggested.
-- =============================================================================

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_clients_clientType')
    ALTER TABLE dbo.clients DROP CONSTRAINT CK_clients_clientType
GO

ALTER TABLE dbo.clients
    ADD CONSTRAINT CK_clients_clientType
    CHECK ([clientType]='lawyer' OR [clientType]='both' OR [clientType]='lender' OR [clientType]='borrower' OR [clientType]='pos')
GO
