from fastapi import APIRouter, Body, Depends

from modules.addresses import addresses_sp, client_addresses_sp, one_address_sp
from security.session_tokens import require_client_rows_access

# Client addresses by source (ine / gps). Written by hand — see modules/addresses.py.
# Personal data: the client themself, staff of that company, or the worker key.
router = APIRouter()
_guard = Depends(require_client_rows_access("addresses", client_may_access=True))

with open("./docs_description/addresses.txt", "r", encoding="utf-8") as file:
    addresses_docstring = file.read()
with open("./docs_description/addresses_client.txt", "r", encoding="utf-8") as file:
    addresses_client_docstring = file.read()
with open("./docs_description/addresses_one.txt", "r", encoding="utf-8") as file:
    addresses_one_docstring = file.read()


@router.post("/addresses", summary="addresses: save (upsert by source) / deactivate",
             description=addresses_docstring, dependencies=[_guard])
def addresses(json_file: dict = Body(...)):
    return addresses_sp(json_file)


@router.post("/addresses/client", summary="active addresses of one client",
             description=addresses_client_docstring, dependencies=[_guard])
def addresses_client(json_file: dict = Body(...)):
    return client_addresses_sp(json_file)


@router.post("/addresses/one", summary="one address by id",
             description=addresses_one_docstring, dependencies=[_guard])
def addresses_one(json_file: dict = Body(...)):
    return one_address_sp(json_file)
