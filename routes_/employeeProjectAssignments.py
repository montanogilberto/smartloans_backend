from fastapi import APIRouter
from modules.employeeProjectAssignments import employee_project_assignments_sp, all_employee_project_assignments_sp, one_employee_project_assignment_sp

router = APIRouter()

# Read employee project assignments docstring from the file
with open("./docs_description/employeeProjectAssignments.txt", "r") as file:
    employee_project_assignments_docstring = file.read()
@router.post("/employee_project_assignments", summary="employee project assignments CRUD", description=employee_project_assignments_docstring)
def employee_project_assignments(json: dict):
    return employee_project_assignments_sp(json)


# Read all employee project assignments docstring from the file
with open("./docs_description/employeeProjectAssignments_all.txt", "r") as file:
    employee_project_assignments_all_docstring = file.read()
@router.get("/all_employee_project_assignments", summary="all employee project assignments", description=employee_project_assignments_all_docstring)
def all_employee_project_assignments():
    return all_employee_project_assignments_sp()


# Read one employee project assignment docstring from the file
with open("./docs_description/employeeProjectAssignments_one.txt", "r") as file:
    employee_project_assignment_one_docstring = file.read()
@router.post("/one_employee_project_assignment", summary="one employee project assignment", description=employee_project_assignment_one_docstring)
def one_employee_project_assignment(json: dict):
    return one_employee_project_assignment_sp(json)
