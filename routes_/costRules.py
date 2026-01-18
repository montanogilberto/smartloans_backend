from fastapi import APIRouter
from modules.costRules import CostRules_sp


router = APIRouter()

# Read CostRules  docstring from the file
with open("./docs_description/costRules.txt", "r") as file:
    CostRules_docstring = file.read()
@router.post("/CostRules",  summary="CostRules CRUD", description=CostRules_docstring)
def CostRules(json: dict):
    return  CostRules_sp(json)