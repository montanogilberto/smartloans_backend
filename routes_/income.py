from fastapi import APIRouter
from modules.income import income_sp, all_income_sp

router = APIRouter()

# Read all income docstring from the file
with open("./docs_description/income_all.txt", "r") as file:
    income_all_docstring = file.read()
@router.get("/all_income",  summary="all income", description=income_all_docstring)
def all_income():
    return  all_income_sp()

# Descripción general de income
with open("./docs_description/income.txt", "r") as file:
    income_docstring = file.read()

@router.post("/income", summary="CRUD de income", description=income_docstring)
def income(json: dict):
    return income_sp(json)