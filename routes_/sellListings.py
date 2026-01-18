from fastapi import APIRouter
from modules.sellListings import sellListings_sp


router = APIRouter()

# Read sellListings  docstring from the file
with open("./docs_description/sellListings.txt", "r") as file:
    sellListings_docstring = file.read()
@router.post("/sellListings",  summary="sellListings CRUD", description=sellListings_docstring)
def sellListings(json: dict):
    return  sellListings_sp(json)