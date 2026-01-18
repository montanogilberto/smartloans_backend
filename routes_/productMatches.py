from fastapi import APIRouter
from modules.productMatches import productMatches_sp


router = APIRouter()

# Read productMatches  docstring from the file
with open("./docs_description/productMatches.txt", "r") as file:
    productMatches_docstring = file.read()
@router.post("/productMatches",  summary="productMatches CRUD", description=productMatches_docstring)
def productMatches(json: dict):
    return  productMatches_sp(json)