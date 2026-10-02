from fastapi import APIRouter
from modules.income import income_sp, all_income_sp, monthly_income_sp
from modules.incomePayments import income_payments_sp

router = APIRouter()

# Read all income docstring from the file
with open("./docs_description/income_all.txt", "r") as file:
    income_all_docstring = file.read()
@router.get("/all_income",  summary="all income", description=income_all_docstring)
def all_income():
    return  all_income_sp()

# Current-month income for one company (Dashboard) — avoids transferring the
# full all-time history that /all_income returns.
# Body: {"income": [{"companyId": N}]}
with open("./docs_description/income_monthly.txt", "r") as file:
    income_monthly_docstring = file.read()
@router.post("/monthly_income", summary="current-month income for a company", description=income_monthly_docstring)
def monthly_income(json: dict):
    return monthly_income_sp(json)

# Descripción general de income
with open("./docs_description/income.txt", "r") as file:
    income_docstring = file.read()

@router.post("/income", summary="CRUD de income", description=income_docstring)
def income(json: dict):
    return income_sp(json)

# Split-payment breakdown for one sale (action 2 = list by incomeId; writes
# happen internally via modules.income's new-income hook, not this route).
# Body: {"incomePayments": [{"action": 2, "incomeId": N}]}
@router.post("/incomePayments", summary="List the payment-method breakdown for a split-payment sale")
def income_payments(json: dict):
    return income_payments_sp(json)