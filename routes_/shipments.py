from fastapi import APIRouter
from modules.shipments import shipments_sp


router = APIRouter()

# Read shipments  docstring from the file
with open("./docs_description/shipments.txt", "r") as file:
    shipments_docstring = file.read()
@router.post("/shipments",  summary="shipments CRUD", description=shipments_docstring)
def shipments(json: dict):
    return  shipments_sp(json)