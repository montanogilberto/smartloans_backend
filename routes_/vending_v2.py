from fastapi import APIRouter
from modules.vending import vending_sp, all_vending_sp

router = APIRouter()

# Read all vending docstring from the file
with open("./docs_description/vendingall.txt", "r") as file:
    vending_all_docstring = file.read()
@router.get("/all_vending",  summary="all vending", description=vending_all_docstring)
def all_vending():
    return  all_vending_sp()

# Descripción general de vending
with open("./docs_description/vending.txt", "r") as file:
    vending_docstring = file.read()

@router.post("/vending", summary="CRUD de vending", description=vending_docstring)
def vending(json: dict):
    return vending_sp(json)