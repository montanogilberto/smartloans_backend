-- Reverts 2026-09-18_backfill_clienttype_pos_companies.sql.
-- WARNING: this reverts by the SAME criteria (companyId scope), not by a
-- saved snapshot of exactly which rows were touched -- if any of these
-- clients has since been given a real clientType change (e.g. correctly
-- moved to 'lender'/'both' by staff), this rollback will NOT touch them
-- (clientType is no longer 'pos' for them) so that's safe. But if a new
-- client was created directly as clientType='pos' in this companyId range
-- AFTER the forward migration ran, this rollback will incorrectly revert
-- that new row back to 'borrower' too, since it can't distinguish
-- "backfilled" from "created as pos afterward". Only run this rollback
-- shortly after the forward migration, before new POS clients accumulate,
-- or re-derive the exact clientId list from the forward migration's
-- preview SELECT output instead of using this blanket version.

UPDATE dbo.clients
SET clientType = 'borrower',
    updated_at = GETUTCDATE()
WHERE clientType = 'pos'
  AND companyId > 0
  AND companyId <> 1008;
