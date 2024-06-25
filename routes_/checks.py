from fastapi import APIRouter
from modules.checks import checks_sp, all_checks_sp, one_checks_sp


router = APIRouter()

# Read checks  docstring from the file
with open("./docs_description/checks.txt", "r") as file:
    checks_docstring = file.read()
@router.post("/checks",  summary="checks CRUD", description=checks_docstring)
def checks(json: dict):
    return  checks_sp(json)


# Read all checks docstring from the file
with open("./docs_description/checks_all.txt", "r") as file:
    checks_all_docstring = file.read()
@router.get("/all_checks",  summary="all checks", description=checks_all_docstring)
def all_checks():
    return  all_checks_sp()


# Read one user docstring from the file
with open("./docs_description/checks_one.txt", "r") as file:
    product_one_docstring = file.read()
@router.post("/one_checks",  summary="one product", description=product_one_docstring)
def one_checks(json: dict):
    return  one_checks_sp(json)