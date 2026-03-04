from fastapi import APIRouter
from modules.companiesBranches import companiesBranches_sp, all_companiesBranches_sp, one_companiesBranches_sp, by_company_companiesBranches_sp

router = APIRouter()

# Read companiesBranches.txt docstring from the file
with open("./docs_description/companiesBranches.txt", "r") as file:
    companiesBranches_docstring = file.read()
@router.post("/companiesBranches", summary="companiesBranches CRUD", description=companiesBranches_docstring)
def companiesBranches(json: dict):
    return companiesBranches_sp(json)


# Read all companiesBranches.txt docstring from the file
with open("./docs_description/companiesBranches_by_company.txt", "r") as file:
    companiesBranches_by_company_docstring = file.read()
@router.post("/companiesBranches_by_company", summary="by_company companiesBranches", description=companiesBranches_by_company_docstring)
def companiesBranches_by_company():
    return by_company_companiesBranches_sp()


# Read all companiesBranches.txt docstring from the file
with open("./docs_description/companiesBranches_all.txt", "r") as file:
    companiesBranches_all_docstring = file.read()
@router.get("/all_companiesBranches", summary="all companiesBranches", description=companiesBranches_all_docstring)
def all_companiesBranches():
    return all_companiesBranches_sp()


# Read one companiesBranches.txt docstring from the file
with open("./docs_description/companiesBranches_one.txt", "r") as file:
    companiesBranches_one_docstring = file.read()
@router.post("/one_companiesBranches", summary="one companiesBranches", description=companiesBranches_one_docstring)
def one_companiesBranches(json: dict):
    return one_companiesBranches_sp(json)
