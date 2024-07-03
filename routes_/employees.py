from fastapi import APIRouter
from modules.employees import employees_sp, all_employees_sp, one_employees_sp

router = APIRouter()

# Read employees docstring from the file
with open("./docs_description/employees.txt", "r") as file:
    employees_docstring = file.read()
@router.post("/employees", summary="employees CRUD", description=employees_docstring)
def employees(json: dict):
    return employees_sp(json)


# Read all employees docstring from the file
with open("./docs_description/employees_all.txt", "r") as file:
    employees_all_docstring = file.read()
@router.get("/all_employees", summary="all employees", description=employees_all_docstring)
def all_employees():
    return all_employees_sp()


# Read one employee docstring from the file
with open("./docs_description/employees_one.txt", "r") as file:
    employee_one_docstring = file.read()
@router.post("/one_employee", summary="one employee", description=employee_one_docstring)
def one_employee(json: dict):
    return one_employee_sp(json)
