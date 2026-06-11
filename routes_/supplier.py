from fastapi import APIRouter
from modules.suppliers import suppliers_sp, all_suppliers_sp, one_suppliers_sp


router = APIRouter()

with open("./docs_description/suppliers.txt", "r") as file:
    suppliers_docstring = file.read()
@router.post("/suppliers", summary="suppliers CRUD", description=suppliers_docstring)
def suppliers(json: dict):
    return suppliers_sp(json)


with open("./docs_description/suppliers_all.txt", "r") as file:
    suppliers_all_docstring = file.read()
@router.post("/all_suppliers", summary="all suppliers", description=suppliers_all_docstring)
def all_suppliers(json: dict):
    return all_suppliers_sp(json)


with open("./docs_description/suppliers_one.txt", "r") as file:
    suppliers_one_docstring = file.read()
@router.post("/one_suppliers", summary="one supplier", description=suppliers_one_docstring)
def one_suppliers(json: dict):
    return one_suppliers_sp(json)
