from fastapi import APIRouter
from modules.departments import departments_sp, all_departments_sp, one_departments_sp

router = APIRouter()

# Read departments docstring from the file
with open("./docs_description/departments.txt", "r") as file:
    departments_docstring = file.read()
@router.post("/departments", summary="departments CRUD", description=departments_docstring)
def departments(json: dict):
    return departments_sp(json)


# Read all departments docstring from the file
with open("./docs_description/departments_all.txt", "r") as file:
    departments_all_docstring = file.read()
@router.get("/all_departments", summary="all departments", description=departments_all_docstring)
def all_departments():
    return all_departments_sp()


# Read one department docstring from the file
with open("./docs_description/departments_one.txt", "r") as file:
    department_one_docstring = file.read()
@router.post("/one_department", summary="one department", description=department_one_docstring)
def one_department(json: dict):
    return one_departments_sp(json)
