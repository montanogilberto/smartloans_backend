from fastapi import APIRouter
from modules.listingDrafts import listingDrafts_sp


router = APIRouter()

# Read buy_offers  docstring from the file
with open("./docs_description/listingDrafts.txt", "r") as file:
    listingDrafts_docstring = file.read()
@router.post("/listingDrafts",  summary="listingDrafts CRUD", description=listingDrafts_docstring)
def listingDrafts(json: dict):
    return  listingDrafts_sp(json)