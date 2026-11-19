from fastapi import APIRouter, Depends
from modules.client_login import (
    send_client_login_code, verify_client_login_code, set_client_password, verify_client_password,
)

from security.rate_limit import rate_limit, row_field


router = APIRouter()

@router.post("/send_client_login_code", summary="Send SMS OTP for POS client self-service login (skipped if firstLoginCompleted)",
             dependencies=[Depends(rate_limit("otp", per_ip=30, per_target=5, window=900,
                                              target=row_field("clientLoginCodes", "phone")))])
def send_code(json: dict):
    return send_client_login_code(json)

# RFC-013: the code and the PIN are 4 digits, so guessing must be throttled per
# phone. Codes also lock after 3 wrong tries in sp_clientLoginCodes; the PIN had
# no limit at all before this.
@router.post("/verify_client_login_code", summary="Verify POS client OTP, auto-provisioning users/userCompanies on first login",
             dependencies=[Depends(rate_limit("otp_verify", per_ip=60, per_target=10, window=900,
                                              target=row_field("clientLoginCodes", "phone")))])
def verify_code(json: dict):
    return verify_client_login_code(json)

@router.post("/set_client_password", summary="First-login onboarding: client sets a password (sp_users action=2)")
def set_password(json: dict):
    return set_client_password(json)

@router.post("/verify_client_password", summary="Returning-client login: phone+password, no OTP",
             dependencies=[Depends(rate_limit("pin", per_ip=30, per_target=5, window=900,
                                              target=row_field("clientPasswordLogin", "phone")))])
def verify_password(json: dict):
    return verify_client_password(json)
