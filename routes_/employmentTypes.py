from fastapi import APIRouter
from modules.employmentTypes import employmentTypes_sp, all_employmentTypes_sp, one_employmentTypes_sp

router = APIRouter()

# Read employment types docstring from the file
with open("./docs_description/employmentTypes.txt", "r") as file:
    employment_types_docstring = file.read()
@router.post("/employment_types", summary="employment types CRUD", description=employment_types_docstring)
def employment_types(json: dict):
    return employmentTypes_sp(json)


# Read all employment types docstring from the file
with open("./docs_description/employmentTypes_all.txt", "r") as file:
    employment_types_all_docstring = file.read()
@router.get("/all_employment_types", summary="all employment types", description=employment_types_all_docstring)
def all_employment_types():
    return all_employmentTypes_sp()


# Read one employment type docstring from the file
with open("./docs_description/employmentTypes_one.txt", "r") as file:
    employment_type_one_docstring = file.read()
@router.post("/one_employment_type", summary="one employment type", description=employment_type_one_docstring)
def one_employment_type(json: dict):
    return one_employmentTypes_sp(json)
