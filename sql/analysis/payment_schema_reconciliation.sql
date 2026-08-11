-- =============================================================================
-- Payment Schema Reconciliation — READ-ONLY ANALYSIS SCRIPT
-- =============================================================================
-- Purpose: independently re-verify, against the LIVE database, the schema
-- drift findings documented in MD/PAYMENT_SCHEMA_RECONCILIATION.md, before
-- PR1b's forward-only migration is authored or run.
--
-- This script contains ONLY SELECT statements. It performs no DDL, no DML,
-- and is safe to run against any environment, including production, without
-- risk of data modification. Run it and compare output against the report
-- before approving PR1b.
--
-- Scope: dbo.bankAccounts, dbo.walletTransactions, dbo.transfers,
-- dbo.clientWallets — the four tables flagged in the non-custodial payments
-- migration's schema-reconciliation phase (PR1a).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Column-level shape of the four tables under review
-- -----------------------------------------------------------------------------
SELECT
    t.name  AS table_name,
    c.name  AS column_name,
    ty.name AS data_type,
    c.max_length,
    c.is_nullable,
    c.column_id
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN ('bankAccounts', 'walletTransactions', 'transfers', 'clientWallets',
                  'bankAccountSnapshots')
ORDER BY t.name, c.column_id;

-- -----------------------------------------------------------------------------
-- 2. All FOREIGN KEY constraints touching these tables (either direction)
-- -----------------------------------------------------------------------------
SELECT
    fk.name                                AS fk_name,
    tp.name                                AS parent_table,
    cp.name                                AS parent_column,
    tr.name                                AS referenced_table,
    cr.name                                AS referenced_column
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.tables tp  ON tp.object_id = fkc.parent_object_id
JOIN sys.columns cp ON cp.object_id = tp.object_id AND cp.column_id = fkc.parent_column_id
JOIN sys.tables tr  ON tr.object_id = fkc.referenced_object_id
JOIN sys.columns cr ON cr.object_id = tr.object_id AND cr.column_id = fkc.referenced_column_id
WHERE tp.name IN ('bankAccounts', 'walletTransactions', 'transfers', 'clientWallets')
   OR tr.name IN ('bankAccounts', 'walletTransactions', 'transfers', 'clientWallets');

-- -----------------------------------------------------------------------------
-- 3. walletTransactions_entryType lookup table — current live vocabulary
-- -----------------------------------------------------------------------------
-- Expected per this analysis: only DEPOSIT / WITHDRAWAL / RESERVE / RELEASE /
-- LOAN_FUNDING / DISBURSEMENT_RECEIVED / REPAYMENT_PRINCIPAL /
-- REPAYMENT_INTEREST / PLATFORM_FEE / REFUND / REVERSAL / ADJUSTMENT /
-- LOAN_REPAYMENT. Confirm CAPITAL_DECLARED / CAPITAL_UNDECLARED /
-- CAPITAL_COMMITTED are ABSENT (that absence is what PR1b adds).
SELECT entryType, description
FROM dbo.walletTransactions_entryType
ORDER BY entryType;

-- -----------------------------------------------------------------------------
-- 4. Row-count / historical-data check on walletTransactions by entryType
-- -----------------------------------------------------------------------------
-- Confirms whether DEPOSIT/WITHDRAWAL rows already exist in production —
-- if any row count here is > 0, PR1b MUST NOT rename or delete these values
-- (Acceptance Criterion: historical integrity — see locked migration plan).
SELECT entryType, COUNT(*) AS row_count, MIN(created_At) AS first_seen, MAX(created_At) AS last_seen
FROM dbo.walletTransactions
GROUP BY entryType
ORDER BY entryType;

-- -----------------------------------------------------------------------------
-- 5. transfers.provider — actual live values in use (comment says stp|stripe,
--    no CHECK constraint enforces it — confirm what's actually stored)
-- -----------------------------------------------------------------------------
SELECT provider, COUNT(*) AS row_count
FROM dbo.transfers
GROUP BY provider;

-- -----------------------------------------------------------------------------
-- 6. clientWallets — confirm it is still the live source for lender matching
-- -----------------------------------------------------------------------------
-- sp_loans_matchLenders.sql:22 joins on this column. Any migration that
-- freezes clientWallets must repoint that query FIRST. This just confirms
-- current row volume / staleness to scope that follow-up work.
SELECT
    COUNT(*)                                   AS wallet_row_count,
    SUM(CASE WHEN availableBalance > 0 THEN 1 ELSE 0 END) AS wallets_with_positive_balance,
    MAX(updatedAt)                             AS most_recent_update
FROM dbo.clientWallets;

-- -----------------------------------------------------------------------------
-- 7. get_balance projection sanity check (dbo.walletTransactions)
-- -----------------------------------------------------------------------------
-- The live sp_walletTransactions_balance action is documented (per this
-- session's code audit) to sum only RESERVE/RELEASE, not the full
-- available/reserved/committed/lent projection. This query independently
-- computes a naive running total per client, to compare against what the SP
-- currently returns for the same clientId when PR1b's regenerated SP lands.
SELECT
    clientId,
    companyId,
    entryType,
    direction,
    SUM(CASE WHEN direction = 'C' THEN amountMXN ELSE -amountMXN END) AS net_amount
FROM dbo.walletTransactions
GROUP BY clientId, companyId, entryType, direction
ORDER BY clientId, companyId, entryType;

-- -----------------------------------------------------------------------------
-- 8. bankAccounts — confirm D18 lifecycle columns are present (added by the
--    hand-written sp_bankAccountsLifecycle.sql exception, not the base PRD)
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN clabeHash IS NOT NULL THEN 1 ELSE 0 END)     AS rows_with_clabeHash,
    SUM(CASE WHEN accountStatus IS NOT NULL THEN 1 ELSE 0 END) AS rows_with_accountStatus
FROM dbo.bankAccounts;

-- -----------------------------------------------------------------------------
-- 9. bankAccountSnapshots — confirm table exists (created by
--    sp_bankAccountsLifecycle.sql, has no corresponding PRD JSON)
-- -----------------------------------------------------------------------------
SELECT COUNT(*) AS snapshot_row_count FROM dbo.bankAccountSnapshots;
