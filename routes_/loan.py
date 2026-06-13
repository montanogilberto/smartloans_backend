from fastapi import APIRouter
from modules.loans import loans_sp, all_loans_sp, one_loans_sp


router = APIRouter()

with open("./docs_description/loans.txt", "r") as file:
    loans_docstring = file.read()
@router.post("/loans", summary="loans CRUD", description=loans_docstring)
def loans(json: dict):
    return loans_sp(json)


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
