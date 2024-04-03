from fastapi import APIRouter
from modules.scannertext import scannertext_sp


router = APIRouter()

# Read login docstring from the file
with open("docs_description/scannertext.txt", "r") as file:
    scannertext_docstring = file.read()

@router.post("/scannertext",  summary="Scanner Text Products", description=scannertext_docstring)
def scannertext(json: dict):
    return  scannertext_sp(json)