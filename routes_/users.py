from fastapi import APIRouter, Depends
from modules.users import users_sp, all_users_sp, one_users_sp, one_users_email_sp, send_recovery_email, send_verification_code, verify_code, check_contact_sp, check_username_sp, send_account_created

from security.rate_limit import field, rate_limit, row_field


router = APIRouter()

# Read users  docstring from the file
with open("./docs_description/users.txt", "r") as file:
    users_docstring = file.read()
@router.post("/users",  summary="users CRUD", description=users_docstring)
def users(json: dict):
    return  users_sp(json)


# Read all users docstring from the file
with open("./docs_description/users_all.txt", "r") as file:
    users_all_docstring = file.read()
@router.get("/all_users",  summary="all users", description=users_all_docstring)
def all_users():
    return  all_users_sp()


# Read one user docstring from the file
with open("./docs_description/users_one.txt", "r") as file:
    user_one_docstring = file.read()
@router.post("/one_users",  summary="one user", description=user_one_docstring)
def one_users(json: dict):
    return  one_users_sp(json)

# Read one user docstring from the file
with open("./docs_description/users_one_email.txt", "r") as file:
    email_user_one_docstring = file.read()
@router.post("/one_users_email",  summary="one user email", description=email_user_one_docstring)
def one_users_email(json: dict):
    return  one_users_email_sp(json)

with open("./docs_description/recovery_email.txt", "r") as file:
    recovery_email_docstring = file.read()
@router.post("/send_recovery_email", summary="Send recovery email", description=recovery_email_docstring,
             dependencies=[Depends(rate_limit("recovery", per_ip=20, per_target=3, window=3600,
                                              target=row_field("users", "email")))])
def send_recovery(json: dict):
    return send_recovery_email(json)

@router.post("/check_contact", summary="Check if phone or email exists in clients/users")
def check_contact(json: dict):
    return check_contact_sp(json)

@router.post("/check_username", summary="Check username availability, suggest alternatives if taken")
def check_username(json: dict):
    return check_username_sp(json)

@router.post("/send_verification_code", summary="Send email OTP for account creation",
             dependencies=[Depends(rate_limit("otp", per_ip=30, per_target=5, window=900,
                                              target=field("target")))])
def send_code(json: dict):
    return send_verification_code(json)

@router.post("/verify_code", summary="Validate email OTP")
def check_code(json: dict):
    return verify_code(json)

@router.post("/send_account_created", summary="Send account-created notice with login username (email/SMS/WhatsApp)",
             dependencies=[Depends(rate_limit("account_created", per_ip=30, per_target=3, window=3600,
                                              target=field("target")))])
def account_created(json: dict):
    return send_account_created(json)
