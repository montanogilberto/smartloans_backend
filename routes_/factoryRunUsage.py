from fastapi import APIRouter
from modules.factoryRunUsages import factoryRunUsages_sp, all_factoryRunUsages_sp, one_factoryRunUsages_sp


router = APIRouter()

with open("./docs_description/factoryRunUsages.txt", "r") as file:
    factoryRunUsages_docstring = file.read()
@router.post("/factoryRunUsages", summary="factoryRunUsages CRUD", description=factoryRunUsages_docstring)
def factoryRunUsages(json: dict):
    return factoryRunUsages_sp(json)


with open("./docs_description/factoryRunUsages_all.txt", "r") as file:
    factoryRunUsages_all_docstring = file.read()
@router.post("/all_factoryRunUsages", summary="all factoryRunUsages", description=factoryRunUsages_all_docstring)
def all_factoryRunUsages(json: dict):
    return all_factoryRunUsages_sp(json)


with open("./docs_description/factoryRunUsages_one.txt", "r") as file:
    factoryRunUsages_one_docstring = file.read()
@router.post("/one_factoryRunUsage", summary="one factoryRunUsage", description=factoryRunUsages_one_docstring)
def one_factoryRunUsage(json: dict):
    return one_factoryRunUsages_sp(json)
