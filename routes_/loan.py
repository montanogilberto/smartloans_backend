import json as json_module

from fastapi import APIRouter
from modules.loans import loans_sp, all_loans_sp, one_loans_sp, _notify_matching_lenders


router = APIRouter()

with open("./docs_description/loans.txt", "r") as file:
    loans_docstring = file.read()
@router.post("/loans", summary="loans CRUD", description=loans_docstring)
async def loans(json: dict):
    response = loans_sp(json)

    action = (json.get("loans") or [{}])[0].get("action")
    if action == 1:
        loan = json_module.loads(response.body)
        if isinstance(loan, dict) and loan.get("loanId") and "error" not in loan:
            await _notify_matching_lenders(loan)

    return response


with open("./docs_description/loans_all.txt", "r") as file:
    loans_all_docstring = file.read()
@router.post("/all_loans", summary="all loans", description=loans_all_docstring)
def all_loans(json: dict):
    return all_loans_sp(json)


with open("./docs_description/loans_one.txt", "r") as file:
    loans_one_docstring = file.read()
@router.post("/one_loans", summary="one loan", description=loans_one_docstring)
def one_loans(json: dict):
    return one_loans_sp(json)
