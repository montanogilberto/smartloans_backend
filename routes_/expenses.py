from fastapi import APIRouter
from modules.expenses import expense_sp, all_expense_sp

router = APIRouter()

# Read all expense docstring from the file
with open("./docs_description/expense_all.txt", "r") as file:
    expense_all_docstring = file.read()
@router.get("/all_expense",  summary="all expense", description=expense_all_docstring)
def all_expense():
    return  all_expense_sp()

# Descripción general de expense
with open("./docs_description/expense.txt", "r") as file:
    expense_docstring = file.read()

@router.post("/expense", summary="CRUD de expense", description=expense_docstring)
def expense(json: dict):
    return expense_sp(json)