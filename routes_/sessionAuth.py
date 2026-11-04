from fastapi import APIRouter, Depends

from modules.sessions import min_native_version, refresh_session
from security.rate_limit import rate_limit

router = APIRouter()


@router.post(
    "/auth/refresh",
    summary="Exchange a refresh token for a new session",
    description="""
{ "refreshToken": str } → 200 { accessToken, refreshToken, expiresIn }
401 log in again · 503 try later (the session is still good)
""",
    dependencies=[Depends(rate_limit("session_refresh", per_ip=600, per_target=0, window=3600))],
)
def auth_refresh(json: dict):
    return refresh_session(json)


@router.get(
    "/app/minVersion",
    summary="Oldest native build allowed to run",
    description="""→ { "ios": int, "android": int }  (build numbers; 0 = no minimum).
Set with MIN_NATIVE_BUILD_IOS / MIN_NATIVE_BUILD_ANDROID.""",
)
def app_min_version():
    return min_native_version()
