-- =============================================================================
-- PR1b — Add CAPITAL_* entryType vocabulary to walletTransactions_entryType
-- =============================================================================
-- Forward-only, additive migration. NOT YET EXECUTED against any database —
-- this file is the reviewable artifact; see MD/PR1B_CAPITAL_VOCABULARY_MIGRATION.md
-- for the full scope boundary and MD/PAYMENT_SCHEMA_RECONCILIATION.md (PR1a,
-- github.com/montanogilberto/smartloans_backend/pull/66) for the verified live
-- baseline this migration is built against.
--
-- SCOPE: adds exactly 3 new rows to the existing dbo.walletTransactions_entryType
-- lookup table. Nothing else. Does not touch existing DEPOSIT/WITHDRAWAL/
-- LOAN_FUNDING/... rows or their historical walletTransactions entries (7 live
-- rows as of 2026-08-11, never rewritten); does not touch clientWallets,
-- bankAccounts/bankAccountSnapshots, transfers/STP, or Stripe; moves no real
-- money.
--
-- Idempotent: mirrors the exact MERGE ... WHEN NOT MATCHED pattern already
-- live in sql/sp_walletTransactions.sql:18-36 — safe to run more than once.
--
-- Semantics (see MD/PAYMENT_SCHEMA_RECONCILIATION.md "Semantic boundary"):
-- these three values describe lender-declared capital availability/commitment
-- state. They must never be interpreted as SmartLoans holding, receiving, or
-- moving the lender's money — no writer of these entryTypes should ever imply
-- custody.
-- =============================================================================

MERGE [dbo].[walletTransactions_entryType] AS t
USING (VALUES
    ('CAPITAL_DECLARED',   14, 'Lender declares capital available to lend -- no money received by SmartLoans'),
    ('CAPITAL_COMMITTED',  15, 'Declared capital committed to a specific loan funding (point of no return: lender has sent SPEI with evidence) -- no money passes through SmartLoans'),
    ('CAPITAL_UNDECLARED', 16, 'Previously declared capital released/withdrawn by the lender -- no money returned by SmartLoans')
) AS s (entryType, sortOrder, description)
ON t.entryType = s.entryType
WHEN NOT MATCHED THEN
    INSERT (entryType, sortOrder, description) VALUES (s.entryType, s.sortOrder, s.description);
GO
