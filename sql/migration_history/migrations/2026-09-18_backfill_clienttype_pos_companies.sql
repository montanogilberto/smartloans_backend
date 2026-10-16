-- =============================================================================
-- Backfill dbo.clients.clientType = 'pos' for existing POS customers that
-- predate the 'pos' clientType value (added by
-- 2026-09-14_add_pos_client_type.sql) and predate the CreateAccount.tsx fix
-- that stopped silently defaulting new POS-profile clients to 'borrower'.
--
-- NOT YET EXECUTED against any database — run manually against
-- smartloansbackend's live DB, same convention as every other file in this
-- migrations/ folder. Forward-only, additive in effect (only ever narrows
-- clientType away from a default that was never a real choice), safe to
-- re-run (WHERE clause only ever matches rows still at 'borrower').
--
-- WHY THIS SCOPE, NOT "every clientType='borrower' row":
-- Live counts checked via GET /all_clients before writing this (read-only,
-- no raw DB query needed):
--   (companyId=0,    clientType='borrower')  98 rows  <- EXCLUDED, see below
--   (companyId=1,    clientType='borrower')  36 rows  <- TARGET
--   (companyId=1008, clientType='borrower')   3 rows  <- EXCLUDED, see below
--   (companyId=1,    clientType='both')       2 rows  <- untouched, explicit choice
--   (companyId=0,    clientType='pos')        2 rows  <- untouched, already correct
--   (companyId=0,    clientType='lender')     1 row   <- untouched, explicit choice
--   (companyId=1008, clientType='lender')     1 row   <- untouched, explicit choice
--   (companyId=1,    clientType='pos')        1 row   <- untouched, already correct
--
-- companyId=1008 IS the SmartLoans company itself -- those 3 rows are real
-- loan participants, not POS customers. Excluded explicitly.
--
-- companyId=0 (98 rows) is deliberately EXCLUDED even though it's the
-- largest group: it is not "no company", it is ambiguous. CreateAccount.tsx
-- itself documents (see the effect near "autoSelectSmartLoans") that step
-- "Acceso" could previously finish with no company selected at all, which
-- is a real, separate, already-fixed bug that historically left real
-- SmartLoans borrowers with companyId=0/unset. Retagging that group risks
-- relabeling genuine loan customers as POS customers -- worse than leaving
-- the label imprecise. If companyId=0 needs a real fix, it needs its own
-- investigation (e.g. cross-referencing dbo.loans), not a blanket guess
-- bundled into this migration.
--
-- companyId=1 (Lavanderia, the one real POS company with clients today) +
-- clientType='borrower' is the clean signal: these clients belong to a POS
-- company (never SmartLoans), and 'borrower' was never a choice anyone
-- made for them -- it was the only value the old CHECK constraint allowed
-- before 2026-09-14, so every POS-created client landed there by default.
--
-- WHERE companyId > 0 AND companyId <> 1008 (not "= 1") so this also
-- covers Vending Agua (2) / FoodTruck (3) or any future POS company
-- automatically -- both currently have zero clients, so today this only
-- matches companyId=1, but the migration doesn't need rewriting when that
-- changes.
-- =============================================================================

-- Preview — run this first and read it before running the UPDATE below.
SELECT clientId, companyId, first_name, last_name, cellphone, clientType, updated_at
FROM dbo.clients
WHERE clientType = 'borrower'
  AND companyId > 0
  AND companyId <> 1008
ORDER BY companyId, clientId;

-- The actual backfill.
UPDATE dbo.clients
SET clientType = 'pos',
    updated_at = GETUTCDATE()
WHERE clientType = 'borrower'
  AND companyId > 0
  AND companyId <> 1008;

-- Verification — row count should match the preview's row count above.
SELECT companyId, clientType, COUNT(*) AS n
FROM dbo.clients
GROUP BY companyId, clientType
ORDER BY companyId, clientType;
