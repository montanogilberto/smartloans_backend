from fastapi import APIRouter
from modules.laundry import laundry_sp, all_laundry_sp

router = APIRouter()

# Read all laundry docstring from the file
with open("./docs_description/laundry_all.txt", "r") as file:
    laundry_all_docstring = file.read()
@router.get("/all_laundry",  summary="all laundry", description=laundry_all_docstring)
def all_laundry():
    return  all_laundry_sp()

# Descripción general de laundry
with open("./docs_description/laundry.txt", "r") as file:
    laundry_docstring = file.read()

@router.post("/laundry", summary="CRUD de laundry", description=laundry_docstring)
def laundry(json: dict):
    return laundry_sp(json)