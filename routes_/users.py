from fastapi import APIRouter
from modules.users import users_sp


router = APIRouter()

# Read login docstring from the file
with open("docs_description/users.txt", "r") as file:
    docstring = file.read()
@router.post("/users",  summary="users CRUD", description=docstring)
def login(json: dict):
    return  users_sp(json)