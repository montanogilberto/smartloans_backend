from fastapi import APIRouter
from modules.expenses import expense_sp, all_expense_sp, monthly_expense_sp, upload_expense_receipt_connector

router = APIRouter()

# Read all expense docstring from the file
with open("./docs_description/expense_all.txt", "r") as file:
    expense_all_docstring = file.read()
@router.get("/all_expense",  summary="all expense", description=expense_all_docstring)
def all_expense():
    return  all_expense_sp()

# One company + one month (the /egresos page and /dashboard KPIs)
with open("./docs_description/expense_monthly.txt", "r") as file:
    expense_monthly_docstring = file.read()
@router.post("/monthly_expense", summary="one month of expenses for a company", description=expense_monthly_docstring)
def monthly_expense(json: dict):
    return monthly_expense_sp(json)

@router.post(
    "/expenses/upload-image",
    summary="Upload a ticket/receipt photo as evidence for an expense",
    tags=["connector"],
)
async def upload_expense_receipt(json: dict):
    return await upload_expense_receipt_connector(json)

# Descripción general de expense
with open("./docs_description/expense.txt", "r") as file:
    expense_docstring = file.read()

@router.post("/expense", summary="CRUD de expense", description=expense_docstring)
def expense(json: dict):
    return expense_sp(json)