# Payment Schema Reconciliation Report

**Status: read-only analysis. No schema, code, or data changes are part of this document or its
companion script.** This is PR1a of the non-custodial payments migration
(`docs/p2p-direct-payments-architecture.md` v1.2 in the `POSVending` frontend repo). PR1b, a
separately reviewed forward-only migration, follows only after this report is reviewed.

## Purpose

Before the non-custodial payments migration runs any posgmo-factory PRD through the pipeline, we
need to know whether the live database already diverges from what the current PRD JSON definitions
expect — a naive re-run of the pipeline is a silent no-op against any table whose `CREATE TABLE` is
already present (all payment-domain tables use `IF NOT EXISTS` guards), so schema drift would
otherwise go undetected. This report documents that drift for `bankAccounts`, `walletTransactions`,
and `transfers`, plus the load-bearing legacy table `clientWallets`, based on static analysis of
the SQL source and Python call sites in this repo. The companion script,
`sql/analysis/payment_schema_reconciliation.sql`, lets anyone independently re-confirm these
findings against the live database with read-only `SELECT` statements before PR1b is authored.

## Method

- Compared each table's `CREATE TABLE` statement in `sql/sp_*.sql` against the corresponding
  `fields` block in the posgmo-factory PRD JSON (`~/Agent_POSGMO/ArchitecturePOSGMO/posgmo-factory/
  tests/prd_*.json`).
- Traced every `.py` and `.sql` file in this repo referencing each table name, to build a
  "who breaks if this changes" dependency map.
- Confirmed mechanically (not assumed) how each table's SP file behaves on re-run: every generated
  SP is `IF OBJECT_ID(...) IS NOT NULL DROP PROCEDURE ...; GO` followed by `CREATE PROCEDURE` (safe
  to redeploy); every `CREATE TABLE` is `IF NOT EXISTS`-guarded (schema changes are silently
  skipped on redeploy unless handled explicitly); lookup tables are seeded via `MERGE ... WHEN NOT
  MATCHED THEN INSERT` with no delete branch (redeploy only ever adds new lookup rows).

## Findings

### `dbo.bankAccounts`

No drift. `prd_bankAccount.json`'s fields (`clientId, clabe, bankCode, bankName, holderName,
isVerified, verificationMethod, verifiedAt, isDefault`) match `sql/sp_bankAccounts.sql:9-27`
exactly.

D18 (CLABE immutable/versioned lifecycle — `PENDING_VERIFICATION → PRIMARY → ARCHIVED`) is not in
the base PRD at all. It's implemented by a separate, hand-written exception file,
`sql/sp_bankAccountsLifecycle.sql`, which `ALTER TABLE`s in `clabeHash`, `rfc`, `accountStatus` and
creates a new table, `dbo.bankAccountSnapshots` (used by RFC-002 to freeze both parties' banking
data at funding-intent creation). Neither of these two columns nor the `bankAccountSnapshots` table
has a corresponding PRD JSON anywhere in posgmo-factory — this is intentional (documented as a
"hand-written infra exception" in the file's own header) but worth stating explicitly here, since a
naive schema diff against the PRD alone would miss it.

**Recommended action**: none required for PR1b. Optional cosmetic fix: `prd_bankAccount.json`'s
`description` field still cites the superseded `payment-banking-first-redesign.md` instead of the
frozen v1.2 doc + RFC-001 — worth fixing in the same edit pass as item 2 below, not a separate PR.

### `dbo.walletTransactions`

Column shape matches `prd_walletTransaction.json` exactly
(`clientId, entryType, direction, amountMXN, referenceType, referenceId, idempotencyKey,
balanceAfter, note` — see `sql/sp_walletTransactions.sql:41-56`). The drift is entirely in two
places:

1. **The `entryType` lookup table** (`sql/sp_walletTransactions.sql`, populated via `MERGE`) only
   contains the legacy vocabulary: `DEPOSIT, RESERVE, RELEASE, LOAN_FUNDING,
   DISBURSEMENT_RECEIVED, REPAYMENT_PRINCIPAL, REPAYMENT_INTEREST, PLATFORM_FEE, WITHDRAWAL,
   REFUND, REVERSAL, ADJUSTMENT, LOAN_REPAYMENT`. The current PRD JSON (edited 2026-08-03,
   posgmo-factory commit `30aea90`) instead specifies `CAPITAL_DECLARED` / `CAPITAL_UNDECLARED` /
   `CAPITAL_COMMITTED` in place of `DEPOSIT`/`WITHDRAWAL`, plus the new `CAPITAL_COMMITTED` value
   for the `reserved → committed` transition that has no equivalent in the live lookup table at
   all today.
2. **The balance-projection logic** (`sp_walletTransactions_balance` action) only sums
   `RESERVE`/`RELEASE` entries — it does not implement the full available/reserved/committed/lent
   4-bucket projection the non-custodial capital ledger design requires
   (`docs/payment-domain-state-machines.md` §1 in the frontend repo).

**Historical data constraint (hard requirement, not a preference)**: `modules/transfers.py` has
already written real production rows using the legacy `DEPOSIT`/`WITHDRAWAL`/`LOAN_FUNDING`/
`REVERSAL` values (query 4 in the companion script quantifies exactly how many, and their date
range). **PR1b must not rename, rewrite, or delete these existing rows.** The correct migration
shape is additive: keep `DEPOSIT`/`WITHDRAWAL` as valid-but-deprecated lookup values (never remove
them from `walletTransactions_entryType` — that would either orphan historical rows or require an
`UPDATE` that rewrites ledger history, which the append-only design forbids on principle), add the
three new `CAPITAL_*` values alongside them, and have all *new* code write only the new vocabulary
going forward.

**Recommended action for PR1b**: re-run `prd_walletTransaction.json` through the posgmo-factory
pipeline (`python orchestrator.py tests/prd_walletTransaction.json`). Confirm post-run that the
lookup `MERGE` is additive (it already is, per the mechanical check above) and that the regenerated
`get_balance`/`sp_walletTransactions_balance` action returns the full 4-bucket shape. Do this as
its own PR, separately reviewed from PR1a.

### `dbo.transfers`

`provider NVARCHAR(20) DEFAULT 'stp'` (`sql/sp_transfers.sql:43`) has no enforced `CHECK`
constraint — `'stp | stripe'` is only a code comment, not a database-level guarantee. The real
issue is scope, not column shape: the current `prd_transfer.json` was already correctly re-scoped
on 2026-08-03 to describe this module as a **deferred future capability** (the eventual "SPEI Auto"
/ platform-initiated payment-initiation feature), explicitly not part of v1 — and its description
no longer lists `stripe` as a legacy fallback provider.

**Recommended action**: **exclude `transfer` from the v1 PRD execution batch entirely.** Do not
regenerate this table's SPs as part of this migration. `dbo.transfers` and
`modules/transfers.py disburse_payment()` stay exactly as they are — frozen, legacy, still
queryable for historical records — until that module is formally retired in a later PR (after the
new SPEI declare/confirm modules replace its callers).

### `dbo.clientWallets` (legacy, no PRD — flagged for completeness)

Not one of the three original tables under review, but load-bearing enough to include here:
`sql/sp_loans_matchLenders.sql:22` contains a live `INNER JOIN dbo.clientWallets w ON
w.clientId = c.clientId AND w.companyId = c.companyId` used directly in lender-matching logic.

This means `clientWallets` **cannot simply be frozen or dropped** once its writers are removed
(as a later migration PR intends) — it still has an active *reader* that gates which lenders get
matched to which loan proposals. Query 6 in the companion script quantifies current row volume so
this dependency can be scoped and repointed to the new capital ledger (`walletTransactions`'
4-bucket projection, once PR1b lands) before any freeze/drop step. This is a required companion
change, not optional cleanup.

## Explicitly Out of Scope for This Report

- `sql/sp_legalCases.sql:167-171` contains a subquery joining `walletTransactions` on a `loanId`
  column that does not exist in that table's schema (confirmed via the column list in query 1 of
  the companion script). This is a pre-existing bug, unrelated to the payment-custody migration.
  **Not addressed here** — flagged for a separate, unrelated fix, per the migration's own scope
  discipline (do not mix an unrelated bug fix into a money-movement migration unless it becomes an
  active blocker during implementation).
- `sql/sp_deleteClientCascade.sql` does not delete `bankAccounts`/`walletTransactions`/`transfers`
  rows when a client is deleted (it does delete `clientWallets` rows). Pre-existing data-integrity
  gap, also out of scope here.

## Summary Table

| Table | Column drift | Scope drift | PR1b action |
|---|---|---|---|
| `bankAccounts` | None | None | No schema change. Optional description fix. |
| `walletTransactions` | `entryType` lookup missing `CAPITAL_*` values; balance projection incomplete | None | Re-run PRD, additive only, never rewrite existing rows |
| `transfers` | None (comment-only, unenforced) | Yes — re-scoped as deferred future capability | Exclude from v1 batch; freeze as legacy |
| `clientWallets` | N/A, no PRD | N/A | Not touched by PR1b; flagged as a required companion change before any future freeze/drop, due to `sp_loans_matchLenders` dependency |

## Verified Live Baseline (2026-08-11)

All 9 queries in `sql/analysis/payment_schema_reconciliation.sql` were run against the live
database and the results independently confirm every finding above. **PR1a is fully verified.**

| Query | Area | Live result |
|---|---|---|
| 1 | Column shapes | Match report exactly — `bankAccounts` has `clabeHash`/`rfc`/`accountStatus`; `bankAccountSnapshots` has the expected loan/party structure |
| 2 | Foreign keys | Exactly the 3 predicted: `transfers.toBankAccountId → bankAccounts`, `walletTransactions.entryType → walletTransactions_entryType`, `transfers.status → transfers_status`. No FK from `walletTransactions` to `transfers`/loans — that link exists only at the application level via `referenceType`/`referenceId` |
| 3 | `entryType` lookup vocabulary | 13 live values (`ADJUSTMENT, DEPOSIT, DISBURSEMENT_RECEIVED, LOAN_FUNDING, LOAN_REPAYMENT, PLATFORM_FEE, REFUND, RELEASE, REPAYMENT_INTEREST, REPAYMENT_PRINCIPAL, RESERVE, REVERSAL, WITHDRAWAL`). `CAPITAL_DECLARED`/`CAPITAL_UNDECLARED`/`CAPITAL_COMMITTED` confirmed absent |
| 4 | Historical row counts | **7 total rows**: `DEPOSIT`×2, `LOAN_FUNDING`×2, `LOAN_REPAYMENT`×1, `REPAYMENT_INTEREST`×1, `REPAYMENT_PRINCIPAL`×1, all dated 2026-07-31/08-01. **Zero `WITHDRAWAL` rows.** Small blast radius today — the right time to do this migration before volume grows |
| 5 | `transfers.provider` | `stp` × 2, no other values in use |
| 6 | `clientWallets` | 8 rows, 1 with a positive balance — confirms this table is still live and small enough to plan a careful migration for, not yet frozen |
| 7 | Wallet accounting baseline | Two clients with real activity (2165: `DEPOSIT +500, LOAN_FUNDING -635, REPAYMENT_INTEREST +4, REPAYMENT_PRINCIPAL +132.01`; 2167: `DEPOSIT +150, LOAN_REPAYMENT -136.01`). Confirms `walletTransactions` is a real financial-movement ledger today, not empty scaffolding — and confirms a naive `SUM()` is not equivalent to "available lender capital" (see semantic boundary below) |
| 8 | `bankAccounts` lifecycle adoption | 4 total rows, all 4 have `accountStatus`, 3/4 have `clabeHash`. The D18 lifecycle implementation (`sp_bankAccountsLifecycle.sql`) is confirmed live and in active use |
| 9 | `bankAccountSnapshots` | 4 rows |

### Semantic boundary this baseline establishes for PR1b

`walletTransactions` today is a **mixed historical financial ledger** — its existing rows
(`DEPOSIT`, `LOAN_FUNDING`, `LOAN_REPAYMENT`, `REPAYMENT_INTEREST`, `REPAYMENT_PRINCIPAL`) describe
real cash movements that happened under the old custodial model. The new `CAPITAL_*` vocabulary
describes a categorically different thing — lender-declared capital *availability/commitment*
state, not money SmartLoans received or holds. Concretely:

- `CAPITAL_DECLARED` — a lender declares capital available to lend. No money changes hands.
- `CAPITAL_COMMITTED` — declared capital is committed to a specific loan funding (the point of no
  return: the lender has sent real SPEI with evidence, per
  `docs/payment-domain-state-machines.md` §1). No money passes through SmartLoans to reach this
  state — it's the borrower's bank receiving the lender's transfer directly.
- `CAPITAL_UNDECLARED` — previously declared capital is released/withdrawn. Again, no money moves
  through SmartLoans.

**PR1b must not reinterpret existing rows to mean this.** `LOAN_FUNDING D -635` for client 2165 in
query 7 stays exactly what it is — a historical financial event under the old model — and is never
rewritten, relabeled, or migrated into a `CAPITAL_COMMITTED` row. The two vocabularies coexist in
the same table going forward; only new writes (from PR2 onward, once `FundingTransaction`/
`LoanPayment` modules exist) use the `CAPITAL_*` values.

### Scope boundary confirmed for PR1b

**In scope**: additive `entryType` lookup rows (`CAPITAL_DECLARED`, `CAPITAL_COMMITTED`,
`CAPITAL_UNDECLARED`) only.

**Explicitly out of scope for PR1b** (deferred to later PRs in the migration sequence, or entirely
out of this migration):
- Dropping or freezing `clientWallets` (8 live rows, 1 positive — real data, still has an active
  reader in `sp_loans_matchLenders.sql`)
- Rewriting, renaming, or deleting any of the 7 historical `walletTransactions` rows
- Renaming `DEPOSIT`/`WITHDRAWAL`/`LOAN_FUNDING` or any other existing `entryType` value
- Adding new foreign keys
- Any change to `bankAccounts`/`bankAccountSnapshots` (the D18 lifecycle work is confirmed live
  and complete — not recreated or modified here). The one `bankAccounts` row missing `clabeHash`
  (3/4 have it) is a pre-existing data-quality observation, not remediated as part of this
  migration — backfilling it here would mix an unrelated data-quality fix into a financial schema
  migration.
- Any change to `transfers`/STP integration or Stripe
- The 4-bucket `available/reserved/committed/lent` balance-projection SP logic — this needs real
  `CAPITAL_*` writers (the `FundingTransaction`/`LoanPayment` modules, later PRs) to be meaningful;
  building it against zero real data now would be premature. Tracked as its own later step in the
  migration sequence ("capital-availability migration").
- Moving any real money

## Before Running PR1b

Confirm what `LOCAL_DB_SERVER` in `posgmo-factory/.env` actually resolves to, and whether it is
the same database this backend's `main → development → qa → production` branches all currently
share (per this repo's own deployment setup — there is no isolated tier to test schema changes
against). Take a backup/snapshot immediately before running the PRD orchestrator regardless of how
additive-safe the SQL in this report appears, and run one PRD module at a time — never the full
`prd_*.json` glob unattended.
