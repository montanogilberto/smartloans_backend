from fastapi import APIRouter
from modules.contractors import contractors_sp, all_contractors_sp, one_contractor_sp

router = APIRouter()

# Read contractors docstring from the file
with open("./docs_description/contractors.txt", "r") as file:
    contractors_docstring = file.read()
@router.post("/contractors", summary="contractors CRUD", description=contractors_docstring)
def contractors(json: dict):
    return contractors_sp(json)


# Read all contractors docstring from the file
with open("./docs_description/contractors_all.txt", "r") as file:
    contractors_all_docstring = file.read()
@router.get("/all_contractors", summary="all contractors", description=contractors_all_docstring)
def all_contractors():
    return all_contractors_sp()


# Read one contractor docstring from the file
with open("./docs_description/contractors_one.txt", "r") as file:
    contractor_one_docstring = file.read()
@router.post("/one_contractor", summary="one contractor", description=contractor_one_docstring)
def one_contractor(json: dict):
    return one_contractor_sp(json)
