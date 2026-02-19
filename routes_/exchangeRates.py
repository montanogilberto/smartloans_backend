from fastapi import APIRouter
from modules.exchangeRates import exchange_rate_sp, exchange_rate_by_day_sp


router = APIRouter()

# Read exchange_rate  docstring from the file
with open("./docs_description/exchange_rate_by_day.txt", "r") as file:
    exchange_rate_by_day_docstring = file.read()
@router.post("/exchange_rate_by_day",  summary="exchange_rate_by_day CRUD", description=exchange_rate_by_day_docstring)
def exchange_rate_by_day(json: dict):
    return  exchange_rate_by_day_sp(json)

# Read exchange_rate  docstring from the file
with open("./docs_description/exchange_rate.txt", "r") as file:
    exchange_rate_docstring = file.read()
@router.post("/exchange_rate",  summary="exchange_rate CRUD", description=exchange_rate_docstring)
def exchange_rate(json: dict):
    return  exchange_rate_sp(json)