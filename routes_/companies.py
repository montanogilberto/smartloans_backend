from fastapi import APIRouter
from modules.companies import companies_sp, all_companies_sp, one_companies_sp

router = APIRouter()

# Read companies docstring from the file
with open("./docs_description/companies.txt", "r") as file:
    companies_docstring = file.read()
@router.post("/companies", summary="companies CRUD", description=companies_docstring)
def companies(json: dict):
    return companies_sp(json)


# Read all companies docstring from the file
with open("./docs_description/companies_all.txt", "r") as file:
    companies_all_docstring = file.read()
@router.get("/all_companies", summary="all companies", description=companies_all_docstring)
def all_companies():
    return all_companies_sp()


# Read one contractor docstring from the file
with open("./docs_description/companies_one.txt", "r") as file:
    companies_one_docstring = file.read()
@router.post("/one_companies", summary="one companies", description=companies_one_docstring)
def one_companies(json: dict):
    return one_companies_sp(json)
