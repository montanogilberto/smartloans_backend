from fastapi import APIRouter
from modules.exchangeRates import exchange_rate_sp


router = APIRouter()

# Read exchange_rate  docstring from the file
with open("./docs_description/exchange_rate.txt", "r") as file:
    exchange_rate_docstring = file.read()
@router.post("/exchange_rate",  summary="exchange_rate CRUD", description=exchange_rate_docstring)
def exchange_rate(json: dict):
    return  exchange_rate_sp(json)