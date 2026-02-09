from fastapi import APIRouter
from modules.cashRegister import cashRegister_sp

router = APIRouter()

with open("./docs_description/cashRegister.txt", "r") as file:
    cashRegister_docstring = file.read()

@router.post("/cashRegister", summary="cashRegister CRUD", description=cashRegister_docstring)
def cashRegister(json: dict):
    return cashRegister_sp(json)
