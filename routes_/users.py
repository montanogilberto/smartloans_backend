from fastapi import APIRouter
from modules.users import users_sp, all_users_sp, one_users_sp


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