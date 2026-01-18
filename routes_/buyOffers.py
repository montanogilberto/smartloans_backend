from fastapi import APIRouter
from modules.buyOffers import buyOffers_sp


router = APIRouter()

# Read buy_offers  docstring from the file
with open("./docs_description/buyoffers.txt", "r") as file:
    buyOffers_docstring = file.read()
@router.post("/buyOffers",  summary="buyOffers CRUD", description=buyOffers_docstring)
def buyOffers(json: dict):
    return  buyOffers_sp(json)