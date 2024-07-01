from fastapi import APIRouter
from modules.departaments import departaments_sp, all_departaments_sp, one_departaments_sp

router = APIRouter()

# Read departaments docstring from the file
with open("./docs_description/departaments.txt", "r") as file:
    departaments_docstring = file.read()
@router.post("/departaments", summary="departaments CRUD", description=departaments_docstring)
def departaments(json: dict):
    return departaments_sp(json)


# Read all departaments docstring from the file
with open("./docs_description/departaments_all.txt", "r") as file:
    departaments_all_docstring = file.read()
@router.get("/all_departaments", summary="all departaments", description=departaments_all_docstring)
def all_departaments():
    return all_departaments_sp()


# Read one departament docstring from the file
with open("./docs_description/departaments_one.txt", "r") as file:
    departaments_one_docstring = file.read()
@router.post("/one_departament", summary="one departaments", description=departaments_one_docstring)
def one_departaments(json: dict):
    return one_departaments_sp(json)
