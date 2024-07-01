from fastapi import APIRouter
from modules.statuses import statuses_sp, all_statuses_sp, one_status_sp

router = APIRouter()

# Read statuses docstring from the file
with open("./docs_description/statuses.txt", "r") as file:
    statuses_docstring = file.read()
@router.post("/statuses", summary="statuses CRUD", description=statuses_docstring)
def statuses(json: dict):
    return statuses_sp(json)


# Read all statuses docstring from the file
with open("./docs_description/statuses_all.txt", "r") as file:
    statuses_all_docstring = file.read()
@router.get("/all_statuses", summary="all statuses", description=statuses_all_docstring)
def all_statuses():
    return all_statuses_sp()


# Read one status docstring from the file
with open("./docs_description/statuses_one.txt", "r") as file:
    status_one_docstring = file.read()
@router.post("/one_status", summary="one status", description=status_one_docstring)
def one_status(json: dict):
    return one_status_sp(json)
