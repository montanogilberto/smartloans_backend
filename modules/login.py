from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
from observability import log_application
from security.session_tokens import issue_session
import json

app = FastAPI()


def _attempted_username(json_file: dict) -> str:
    """Best-effort attempted-username extraction for the security log."""
    for key in ("username", "user", "name", "email"):
        val = json_file.get(key)
        if val:
            return str(val)
    try:
        return str((json_file.get("users") or [{}])[0].get("username", "") or "")
    except (TypeError, IndexError, AttributeError):
        return ""


def _attach_session(result: object) -> None:
    """A valid login carries session tokens in its row; a failed one never does."""
    rows = result.get("result") if isinstance(result, dict) else None
    row = rows[0] if isinstance(rows, list) and rows else None
    if not isinstance(row, dict) or row.get("error") or not str(row.get("userId") or "").isdigit():
        return
    session = issue_session(row["userId"], row.get("companyId"), row.get("clientId"), row.get("roleCode"))
    if session:
        row["session"] = session


def login_sp(json_file: dict):
    conn = None
    cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_login @pjsonfile = %s", (json.dumps(json_file),))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)
        _attach_session(result)

        # Security event: a failed login attempt (durable path). The password is
        # NEVER logged — only the attempted username, the reason and (via context)
        # the source IP. A per-account attempt counter / lockout is a follow-up.
        try:
            msg = str(result.get("msg", "")) if isinstance(result, dict) else ""
            has_user = bool(result.get("userId")) if isinstance(result, dict) else False
            low = msg.lower()
            if (not has_user) or "invalid" in low or "incorrect" in low:
                log_application(
                    "SECURITY", "login",
                    f"Failed login attempt for '{_attempted_username(json_file)}': {msg or 'no user match'}",
                )
        except Exception:
            pass

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass
        try:
            if conn:
                conn.close()
        except Exception:
            pass
