from fastapi import APIRouter
from modules.client_login import send_client_login_code, verify_client_login_code, set_client_password


router = APIRouter()

@router.post("/send_client_login_code", summary="Send SMS OTP for POS client self-service login")
def send_code(json: dict):
    return send_client_login_code(json)

@router.post("/verify_client_login_code", summary="Verify POS client OTP, auto-provisioning users/userCompanies on first login")
def verify_code(json: dict):
    return verify_client_login_code(json)

@router.post("/set_client_password", summary="First-login onboarding: client sets a password (sp_users action=2)")
def set_password(json: dict):
    return set_client_password(json)
