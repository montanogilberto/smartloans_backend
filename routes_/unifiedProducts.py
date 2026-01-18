from fastapi import APIRouter
from modules.unifiedProducts import unifiedProducts_sp


router = APIRouter()

# Read unifiedProducts  docstring from the file
with open("./docs_description/unifiedProducts.txt", "r") as file:
    unifiedProducts_docstring = file.read()
@router.post("/unifiedProducts",  summary="unifiedProducts CRUD", description=unifiedProducts_docstring)
def unifiedProducts(json: dict):
    return  unifiedProducts_sp(json)