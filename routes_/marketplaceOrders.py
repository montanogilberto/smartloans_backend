from fastapi import APIRouter
from modules.marketplaceOrders import marketplaceOrders_sp


router = APIRouter()

# Read buy_offers  docstring from the file
with open("./docs_description/marketplaceOrders.txt", "r") as file:
    marketplaceOrders_docstring = file.read()
@router.post("/marketplaceOrders",  summary="marketplaceOrders CRUD", description=marketplaceOrders_docstring)
def marketplaceOrders(json: dict):
    return  marketplaceOrders_sp(json)