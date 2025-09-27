from fastapi import APIRouter
from modules.contact_email import send_contact_email

router = APIRouter()

with open("./docs_description/contact_email.txt", "r") as file:
    contact_email_docstring = file.read()
@router.post("/contact_email", summary="Contact email", description=contact_email_docstring)
def send_recovery(json: dict):
    return send_contact_email(json)