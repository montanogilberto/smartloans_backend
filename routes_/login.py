from fastapi import APIRouter
from modules.login import login_sp


router = APIRouter()

# Read login docstring from the file
with open("docs_description/login.txt", "r") as file:
    login_docstring = file.read()
@router.post("/login",  summary="users validation", description=login_docstring)
def login(json: dict):
    return  login_sp(json)