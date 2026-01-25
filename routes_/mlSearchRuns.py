from fastapi import APIRouter
from modules.mlSearchRuns import mlSearchRuns_sp

router = APIRouter()

# Read docstring from file (optional)
with open("./docs_description/mlSearchRuns.txt", "r") as file:
    mlSearchRuns_docstring = file.read()

@router.post("/mlSearchRuns", summary="ML Search Runs CRUD", description=mlSearchRuns_docstring)
def mlSearchRuns(json: dict):
    return mlSearchRuns_sp(json)
