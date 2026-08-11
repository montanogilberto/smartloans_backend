# PR1b — Capital Vocabulary Migration

**Status: drafted, NOT executed.** The migration script in this PR has not been run against any
database. This document plus the SQL files are the reviewable artifact; execution is a separate,
explicit step after review, per the non-custodial payments migration's own risk register (shared
database across `main`/`development`/`qa`/`production`, no isolated tier to test against).

Builds on the verified baseline in
[PAYMENT_SCHEMA_RECONCILIATION.md](./PAYMENT_SCHEMA_RECONCILIATION.md) / PR1a
(`github.com/montanogilberto/smartloans_backend/pull/66`), which confirmed live:
- 7 historical `walletTransactions` rows (`DEPOSIT`×2, `LOAN_FUNDING`×2, `LOAN_REPAYMENT`×1,
  `REPAYMENT_INTEREST`×1, `REPAYMENT_PRINCIPAL`×1) — zero `WITHDRAWAL` rows.
- The live `entryType` lookup table confirmed missing `CAPITAL_DECLARED`/`CAPITAL_UNDECLARED`/
  `CAPITAL_COMMITTED`.
- `clientWallets`: 8 rows, 1 positive balance, still live with an active reader in
  `sp_loans_matchLenders.sql` — not touched by this PR.

## What this PR contains

`sql/migrations/2026-08-11_add_capital_vocabulary.sql` — a single, additive `MERGE ... WHEN NOT
MATCHED` statement adding exactly 3 rows to `dbo.walletTransactions_entryType`:

| entryType | sortOrder | Meaning |
|---|---|---|
| `CAPITAL_DECLARED` | 14 | Lender declares capital available to lend. No money changes hands. |
| `CAPITAL_COMMITTED` | 15 | Declared capital committed to a specific loan funding — the point of no return per `docs/payment-domain-state-machines.md` §1: the lender has sent real SPEI with evidence. Money moves lender→borrower directly; SmartLoans never receives or holds it. (Stored `description` is a shortened 93-char form — `NVARCHAR(100)`, see incident note below.) |
| `CAPITAL_UNDECLARED` | 16 | Previously declared capital released/withdrawn. No money returned by SmartLoans, because none was ever held. |

`sql/migrations/2026-08-11_add_capital_vocabulary_ROLLBACK.sql` — the reverse. Includes a mandatory
guard query that must return zero rows before the `DELETE` is allowed to run (protects against
deleting a lookup value that real ledger rows already reference by the time a rollback is
considered).

This PR authored the migration by hand, as a small, tightly-scoped, additive-only script — the
same "hand-written infra exception, evolves an existing table" pattern already established by
`sql/sp_bankAccountsLifecycle.sql` for the `bankAccounts` D18 work — rather than regenerating
`sql/sp_walletTransactions.sql` through the full posgmo-factory pipeline. Rationale: the pipeline
regenerates the entire SP file (insert/get_balance/list actions, not just the lookup table), which
is a larger blast radius than this PR's scope requires, and this table already has real production
data (§ below) where an exactly-predictable, line-by-line-reviewable diff matters more than pipeline
convention.

## What this PR explicitly does NOT contain

Per the scope boundary established during PR1a review:

- ❌ Drop or freeze `clientWallets` (8 live rows, still has an active reader)
- ❌ Rewrite, rename, or delete any of the 7 historical `walletTransactions` rows
- ❌ Rename `DEPOSIT`, `WITHDRAWAL`, `LOAN_FUNDING`, or any other existing `entryType` value
- ❌ Add any new foreign key
- ❌ Touch `bankAccounts` / `bankAccountSnapshots` (D18 lifecycle confirmed live and complete — the
  one `bankAccounts` row missing `clabeHash`, 3/4 have it, is a pre-existing data-quality
  observation, not remediated here)
- ❌ Touch `transfers` / STP integration or Stripe
- ❌ Build the 4-bucket `available/reserved/committed/lent` balance-projection SP logic — deferred
  to the "capital-availability migration" step later in the sequence, once real `FundingTransaction`/
  `LoanPayment` writers exist to make that projection meaningful against real data
- ❌ Move any real money
- ❌ Execute the migration script against any database

## Critical semantic rule (carried into every future writer of these values)

A `CAPITAL_*` entry must never imply that SmartLoans received or holds the lender's money. The
existing rows in this table (`DEPOSIT`, `LOAN_FUNDING`, etc.) describe real cash movements under
the old custodial model and are explicitly preserved as historical fact, unmodified. The new
`CAPITAL_*` vocabulary describes a different concept — declared/committed capital *state* — and the
two vocabularies coexist in the same table without one reinterpreting the other.

## Incident note (2026-08-11)

First execution attempt against the live DB failed: `Msg 8152 — String or binary data would be
truncated`. Root cause: the original `CAPITAL_COMMITTED` description was ~148 characters, over the
`description NVARCHAR(100)` column limit (confirmed against `sql/sp_walletTransactions.sql:14`).
Since `MERGE` validates the full `VALUES` set before inserting, the statement rolled back
atomically — **zero rows were inserted**, no partial state. Fixed by shortening the description to
93 characters (all three values now verified: 76 / 93 / 95 characters, `NVARCHAR(100)` limit).

## Execution checklist (for whoever runs this, later, as its own explicit step)

1. Confirm this PR has been reviewed and approved.
2. Confirm the target database is the intended one (see PR1a's note on `LOCAL_DB_SERVER` /
   shared-environment risk).
3. Take a backup/snapshot immediately before running.
4. Run `sql/migrations/2026-08-11_add_capital_vocabulary.sql`.
5. Re-run query 3 from `sql/analysis/payment_schema_reconciliation.sql` to confirm the 3 new rows
   are present and every pre-existing row is unchanged.
6. Re-run query 4 to confirm the 7 historical rows are byte-for-byte unchanged.
