"""
Global environment flag for the backend.

APP_ENV  dev  -> local backend (python main.py, uvicorn :8000) against the DEV database
         prod -> Azure App Service smartLoansBackend against the PRODUCTION database
(default prod, so Azure keeps working without any new App Setting.)

Which database is used is still decided only by LOCAL_DB_SERVER / LOCAL_DB_NAME /
LOCAL_DB_USER / LOCAL_DB_PASSWORD (see databases.py): local .env -> dev DB,
Azure App Settings -> prod DB. APP_ENV labels the process so logs, CORS and any
env-specific behavior can branch on it.
"""
import os

APP_ENV: str = (os.getenv("APP_ENV") or "prod").strip().lower()
IS_PROD: bool = APP_ENV == "prod"
IS_DEV: bool = not IS_PROD

# Scheduled jobs (daily charge_due, client reminders, funding sweeps) act on
# whatever DB LOCAL_DB_* points to. Run them only in prod so a local backend
# never double-charges or double-notifies; ENABLE_SCHEDULER=true/false overrides.
_scheduler_flag = (os.getenv("ENABLE_SCHEDULER") or "").strip().lower()
SCHEDULER_ENABLED: bool = (
    _scheduler_flag in ("1", "true", "yes") if _scheduler_flag else IS_PROD
)

# Extra CORS origins for this environment (comma-separated), e.g. the DEV/QA
# Static Web App URLs:  CORS_EXTRA_ORIGINS=https://xxx.azurestaticapps.net,https://yyy...
CORS_EXTRA_ORIGINS: list[str] = [
    o.strip().rstrip("/") for o in os.getenv("CORS_EXTRA_ORIGINS", "").split(",") if o.strip()
]


def describe() -> str:
    """One-line startup banner: which env and which DB this process talks to."""
    return (
        f"APP_ENV={APP_ENV} "
        f"DB={os.getenv('LOCAL_DB_SERVER', '?')}/{os.getenv('LOCAL_DB_NAME', '?')} "
        f"SCHEDULER={'on' if SCHEDULER_ENABLED else 'off'}"
    )
