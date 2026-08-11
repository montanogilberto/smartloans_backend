-- =============================================================================
-- ROLLBACK for 2026-08-11_add_capital_vocabulary.sql
-- =============================================================================
-- SAFE ONLY if no walletTransactions row has yet been written with one of
-- these 3 entryType values (i.e. before any FundingTransaction/LoanPayment
-- writer from a later PR ships and starts using them).
--
-- ALWAYS run the guard query below FIRST. If it returns any row with
-- row_count > 0, STOP — do not proceed with the DELETE. Deleting a lookup
-- value that is FK-referenced by real ledger entries would violate
-- FK_walletTransactions_entryType, and more importantly would silently
-- orphan real financial/capital-commitment history — the same "never
-- rewrite history" principle that governs the existing DEPOSIT/WITHDRAWAL
-- rows applies here the moment these new values have real usage.
-- =============================================================================

-- Guard — expected result: zero rows.
SELECT entryType, COUNT(*) AS row_count
FROM dbo.walletTransactions
WHERE entryType IN ('CAPITAL_DECLARED', 'CAPITAL_COMMITTED', 'CAPITAL_UNDECLARED')
GROUP BY entryType;

-- Only proceed past this point if the guard query above returned nothing.
DELETE FROM [dbo].[walletTransactions_entryType]
WHERE entryType IN ('CAPITAL_DECLARED', 'CAPITAL_COMMITTED', 'CAPITAL_UNDECLARED');
GO
