from fastapi import APIRouter
from modules.buyOffers import buy_offers_sp


router = APIRouter()

# Read buy_offers  docstring from the file
with open("./docs_description/buyoffers.txt", "r") as file:
    buy_offers_docstring = file.read()
@router.post("/buy_offers",  summary="buy_offers CRUD", description=buy_offers_docstring)
def buy_offers(json: dict):
    return  buy_offers_sp(json)