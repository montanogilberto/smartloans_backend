# smartloans_backend

FastAPI backend for SmartLoans and POS GMO (laundry, vending, rewards, WhatsApp bot).
Adds to `~/.claude/CLAUDE.md`; this file wins on conflict.

**This repo is public.** Every commit, branch and PR is readable by anyone.

## Layout
- `main.py` — app, CORS origins, middleware, router registration, APScheduler jobs.
  A new router must be imported and `app.include_router(...)`-ed here.
- `routes_/<name>.py` — thin FastAPI routers. Endpoint descriptions are read from
  `docs_description/<name>.txt` at import time (the file must exist or the app won't start).
  `routes/` is legacy (one file); don't add to it.
- `modules/<name>.py` — logic. DB calls go through `databases.connection()` and
  `EXEC [dbo].[sp_*] @pjsonfile = %s` only.
- `sql/` — SP scripts (`sp_*.sql`) and `sql/migrations/` (dated table/column changes).
  `sql_logic/` and `sql/migration_history/` are older; new scripts go in `sql/`.
- `observability/` — request middleware + log writer (`MD/OBSERVABILITY.md`).
- `security/worker_key.py` — `require_worker_key` (`X-Worker-Key` header) for
  internal/worker-only endpoints.

## Database
- `databases.py` connects with `LOCAL_DB_*` env vars, **autocommit on**. `SafeCursor`
  inlines the `@pjsonfile` JSON to work around a FreeTDS crash — keep the
  single-param `EXEC ... @pjsonfile = %s` shape so it applies.
- CI (`scripts/check_raw_sql.py`) fails the build on raw SQL in Python. Its detector is
  a verbatim copy of posgmo-factory's reviewer — change both together.
- **The backend never runs SQL files.** Scripts are run by hand in SSMS / Azure Data
  Studio, in the order the script header or the `sql/migrations/README_*.md` gives.
  No `/migrate` endpoints, no `run_migration()` (`tests/test_no_sql_file_migrations.py`).
- Every script must be safe to re-run (`IF COL_LENGTH(...) IS NULL`, `IF OBJECT_ID(...)`).
  Destructive migrations ship with a `_ROLLBACK.sql` next to them.
- A migration's header says why, which code writes/reads it, the run order, and the rollback.
- `CREATE PROCEDURE` fails on a missing *column* of an existing table (Msg 207) but not
  on a missing *table* (deferred resolution) — an SP that compiled can still fail at
  runtime. After deploying, check every table it reads exists.
- SP response shape: one `jsonResult` column, `{"result":[{"<entity>":[...]}]}`, errors
  as `{"error":"..."}` from the `CATCH` block.

## Environments
- `APP_ENV` (`app_env.py`): `prod` (default, Azure) or `dev`. The DB is chosen only by
  `LOCAL_DB_*`. The `[appEnv][startup]` line shows which DB the process uses.
- Branches: work on `development` → PR to `main`. A push to `main` deploys to Azure
  App Service `smartLoansBackend` (`.github/workflows/main_smartloansbackend.yml`).
- Prod logs: App Service log stream. A 500 with `Could not find stored procedure` /
  `Invalid column name` means the SQL scripts weren't run on that DB.
- The scheduler (daily repayments, reminders) needs App Service "Always On".

## Auth
There is no auth middleware. `X-User-Id` / `X-Company-Id` / `X-Client-Id` headers are
for observability only — never authorize on them. Endpoints that mutate config or run
jobs take `Depends(require_worker_key)`.

## Run & test
```bash
venv/bin/python main.py                               # uvicorn :8000, reload
venv/bin/python -m unittest discover tests -v         # tests (unittest, no pytest)
venv/bin/python scripts/check_raw_sql.py              # same check CI runs
```
Before calling a change done: the tests touching it pass, `check_raw_sql.py` passes,
and the app imports (`venv/bin/python -c "import main"`).

## Integrations
- WhatsApp: Meta Cloud API (`modules/whatsappCloud.py`); inbound messages are routed
  by `phone_number_id` to `sp_whatsappChannels` (`POST /whatsapp/channels`, cached 5 min).
  SMS still via Twilio (`modules/ticket_notifications.py`).
- Push: Azure Notification Hubs (`MD/PUSH_NOTIFICATIONS.md`).
