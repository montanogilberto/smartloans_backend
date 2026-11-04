"""Session renewal and the native app's minimum version.

Tokens are stateless, so renewal is where a deactivated user loses access: the
refresh token alone is not enough, dbo.users must still say the account is active.
"""
import json
import logging
import os

from fastapi.responses import JSONResponse

from databases import connection
from security.session_tokens import decode, reissue_session

logger = logging.getLogger("sessions")

_EXPIRED = "Tu sesión expiró. Inicia sesión de nuevo."


def _user_row(user_id: str) -> dict | None:
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_users_one @pjsonfile = %s", (json.dumps({"users": [{"userId": user_id}]}),))
        # FOR JSON splits long results across rows.
        text = "".join(row[0] for row in cursor.fetchall() if row and row[0])
        rows = json.loads(text).get("users") if text else None
        return rows[0] if rows else None
    finally:
        if conn:
            conn.close()


def refresh_session(json_file: dict) -> JSONResponse:
    """POST /auth/refresh — { "refreshToken": str } → { accessToken, refreshToken, expiresIn }.
    401 means log in again. 503 means try later: the session is still good."""
    claims = decode(json_file.get("refreshToken"), "refresh")
    if claims is None:
        return JSONResponse({"error": _EXPIRED}, status_code=401)
    try:
        user = _user_row(claims["sub"])
    except Exception:
        logger.exception("[sessions] user lookup failed")
        return JSONResponse({"error": "No se pudo renovar la sesión"}, status_code=503)
    if not user or str(user.get("active")) not in ("1", "True", "true"):
        return JSONResponse({"error": _EXPIRED}, status_code=401)
    session = reissue_session(claims)
    if session is None:
        return JSONResponse({"error": "No se pudo renovar la sesión"}, status_code=503)
    return JSONResponse(session, status_code=200)


def _build_setting(name: str) -> int:
    try:
        return max(0, int(os.getenv(name, "0")))
    except ValueError:
        return 0


def min_native_version() -> JSONResponse:
    """GET /app/minVersion — native builds below these must update. 0 = no minimum."""
    return JSONResponse({"ios": _build_setting("MIN_NATIVE_BUILD_IOS"),
                         "android": _build_setting("MIN_NATIVE_BUILD_ANDROID")}, status_code=200)
