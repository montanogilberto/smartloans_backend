from fastapi import APIRouter
from modules.sellListings import sellListings_sp, all_sellListings_sp, query_sellListings_sp


router = APIRouter()

# Read sellListings  docstring from the file
with open("./docs_description/sellListings.txt", "r") as file:
    sellListings_docstring = file.read()
@router.post("/sellListings",  summary="sellListings CRUD", description=sellListings_docstring)
def sellListings(json: dict):
    return  sellListings_sp(json)

# Read all statuses docstring from the file
with open("./docs_description/sellListings_all.txt", "r") as file:
   sellListings_all_docstring = file.read()
@router.get("/all_sellListings", summary="all sellListings", description=sellListings_all_docstring)
def all_selllisting():
    return all_sellListings_sp()


# Read one status docstring from the file
with open("./docs_description/sellListings_query.txt", "r") as file:
    sellListings_query_docstring = file.read()
@router.post("/query_sellListings", summary="query sellListings", description=sellListings_query_docstring)
def query_sellListings(json: dict):
    return query_sellListings_sp(json)
