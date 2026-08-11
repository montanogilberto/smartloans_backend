# PR2 — `paymentIntents` (Hand-Authored, Documented Factory Exception)

**Status: drafted, NOT executed.** `sql/sp_paymentIntents.sql` has not been run against any
database. This document plus the SQL file are the reviewable artifact.

## Why this is hand-authored instead of posgmo-factory-generated

Two export-only factory runs against `tests/prd_paymentIntent.json` (2026-08-11) confirmed the
pipeline cannot yet propagate this module's requirements end-to-end, even after fixing two real
bugs found along the way:

1. `architect_agent` initially hallucinated `FK_paymentIntents_companies` — a table that doesn't
   exist in this schema. **Fixed**: added an explicit rule to `agents/architect/prompt.py`
   (`companyId` is never an FK in this schema).
2. `decision_gate/rules.py` crashed (`TypeError: 'NoneType' object is not iterable`) on a spec
   field the LLM returned as explicit `null` rather than omitted. **Fixed**: hardened every
   `.get(key, default)` call site in that file to `.get(key) or default`, which only guards a
   missing key, not an explicit `null`.

With both of those fixed, the pipeline ran cleanly end-to-end and `decision_gate` returned
`status: APPROVED` (tier `TIER_2_FINANCIAL`) — a genuine, non-bypassed approval, not a repeat of
the earlier bug. But the resulting SQL was still incomplete on review: `backend_pattern` came back
`CRUD_ONLY`, missing the `expire_due`/`cancel`/`list` actions, the `CHECK` constraints, and the
unique-FUNDING-per-loan index that `prd_paymentIntent.json.database.hints[]` explicitly documents.
Root cause, traced fully:

- `architect/prompt.py`'s "PRD hints — always forward these from the incoming PRD" section forwards
  `prd.backend.endpoints[]`, `prd.database.tables[]`, and `prd.database.storedProcedures[]` — but
  **never `prd.database.hints[]`**. The hints this PRD actually uses to carry its requirements are
  silently dropped before `architect` ever sees them.
- Even if they were forwarded, `decision_gate/rules.py`'s `_classify_backend_pattern()` **has no
  code path that returns `"ACTION_ROUTER"` at all** — it only ever returns `"CRUD_ONLY"` or
  `"CRUD_AND_CONNECTOR"`. `database_agent`'s own prompt fully supports generating `ACTION_ROUTER`
  SQL once that classification fires (`"For ACTION_ROUTER SP pattern — when
  gate_result.backend_pattern == 'ACTION_ROUTER'"`), but nothing in the pipeline can ever set that
  value today.

This is an incomplete factory feature, not a bug in something that used to work — building it
properly (hints propagation + real ACTION_ROUTER classification + deterministic invariant
enforcement) is real, separate scope, tracked as posgmo-factory tech debt, not part of this PR.
**The generated SQL from that run was discarded — nothing in this file is copied from it.**

## Source contracts

Everything below is derived directly from:
- `docs/p2p-direct-payments-architecture.md` v1.2 — D12 (5-day funding expiry), D14 (every
  declaration born from a `paymentIntent`)
- `docs/rfcs/RFC-002-funding-workflow.md` — `sp_paymentIntents (create/expire_due/cancel/list)`
- `docs/rfcs/RFC-003-payment-intents.md`
- `posgmo-factory/tests/prd_paymentIntent.json` — field list and `database.hints[]`

Style follows the existing hand-authored precedent in this codebase, `sql/sp_disbursement.sql`
(single action-router SP, string `@action`, `DATETIME2`/`GETUTCDATE()`, `FOR JSON PATH,
WITHOUT_ARRAY_WRAPPER` / `FOR JSON PATH` result shape) — not the generic factory CRUD template.

## Requirements checklist

| Requirement (from `database.hints`/RFC-002) | Where implemented |
|---|---|
| State machine: `OPEN → DECLARED \| EXPIRED \| CANCELLED`, any other transition errors | `CK_paymentIntents_status` bounds the value set; the SP only ever writes `EXPIRED` (from `expire_due`, `OPEN`-only) or `CANCELLED` (from `cancel`, `OPEN`-only) — no code path writes any other transition. `DECLARED` is written by `fundingTransaction`/`loanPayment`'s own `declare` action (future PR), not by this SP. |
| `expire_due` — marks `OPEN` + `expiresAt` passed as `EXPIRED`, returns affected `loanId`s | Implemented via `OUTPUT ... INTO @expired`, returned as a JSON array. |
| `cancel` | Implemented, `OPEN`-only guard before the `UPDATE`. |
| `list` (`list_for_loan`) | Implemented, scoped to `companyId` + `loanId`. |
| Only one `FUNDING` intent per loan | `UQ_paymentIntents_openFunding`, a unique filtered index on `(companyId, loanId) WHERE intentType='FUNDING' AND status='OPEN'` — scoped to `OPEN` specifically so an `EXPIRED`/`CANCELLED` `FUNDING` intent doesn't block a new one for the same loan after the loan returns to the marketplace. |
| `intentType`/`status` allowed values are `CHECK` constraints, not lookup tables | `CK_paymentIntents_intentType`, `CK_paymentIntents_status`. |
| Index `(status, expiresAt)` for the expiry cron sweep | `IX_paymentIntents_expirySweep`, filtered to `status='OPEN'`. |
| Idempotency | The unique filtered index is the idempotency mechanism for `FUNDING` — a duplicate `create` call for an already-open FUNDING intent is rejected with a friendly message (checked explicitly before insert, and again as a `CATCH` fallback on error 2601/2627 in case of a race). |
| Non-custodial boundary | No Stripe/STP/wallet call anywhere in this file — the SP only ever reads/writes `dbo.paymentIntents`. |

## What this PR does NOT do

- No Ionic page, side-menu entry, `App.tsx`/`Setting.tsx`/`rolePermissions` changes, or any other
  frontend scaffolding — `paymentIntent` is a domain primitive consumed by the existing P2P lending
  pages (per the earlier finding that the factory's generic frontend/PR stages treat every module
  as a new standalone CRUD feature, which is wrong for this one).
- No changes to `fundingTransaction`/`loanPayment` — those are separate, later PRs; `declare`
  (`OPEN → DECLARED`) is their responsibility, not this SP's.
- No execution against any database.
- No fix to the posgmo-factory `database.hints` propagation / `ACTION_ROUTER` classification gap —
  documented above as tech debt, not addressed here.

## Before executing (whenever that's decided separately)

1. Confirm `dbo.loans`, `dbo.loanInstallments`, `dbo.clients`, `dbo.bankAccountSnapshots` all exist
   with the exact PK column names referenced in the FKs above (`loanId`, `installmentId`,
   `clientId`, `snapshotId`) — all four were independently confirmed as valid FK targets by
   `schema_analyst_agent` across every export-only run this session, but worth a final direct check
   before running DDL.
2. Take a backup/snapshot, same as PR1a/PR1b.
3. Run in a controlled window, then verify: `SELECT * FROM sys.objects WHERE name IN
   ('paymentIntents','sp_paymentIntents','UQ_paymentIntents_openFunding',
   'IX_paymentIntents_expirySweep')` — confirm all four exist and nothing else was affected.
