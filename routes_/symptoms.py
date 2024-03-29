from fastapi import APIRouter
from modules.api_gpt import symptoms_sp


router = APIRouter()

# Read login docstring from the file
with open("docs_description/symptoms.txt", "r") as file:
    symptoms_docstring = file.read()

@router.post("/symptoms",  summary="Medical Recomenations", description=symptoms_docstring)
def symptoms(json: dict):
    return  symptoms_sp(json)