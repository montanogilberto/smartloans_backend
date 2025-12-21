from fastapi import APIRouter
from modules.clients import clients_sp, all_clients_sp, one_clients_sp


router = APIRouter()

# Read clients  docstring from the file
with open("./docs_description/clients.txt", "r") as file:
    clients_docstring = file.read()
@router.post("/clients",  summary="clients CRUD", description=clients_docstring)
def clients(json: dict):
    return  clients_sp(json)


# Read all clients docstring from the file
with open("./docs_description/clients_all.txt", "r") as file:
    clients_all_docstring = file.read()
@router.get("/all_clients",  summary="all clients", description=clients_all_docstring)
def all_clients():
    return  all_clients_sp()


# Read one user docstring from the file
with open("./docs_description/clients_one.txt", "r") as file:
    product_one_docstring = file.read()
@router.post("/one_clients",  summary="one product", description=product_one_docstring)
def one_clients(json: dict):
    return  one_clients_sp(json)