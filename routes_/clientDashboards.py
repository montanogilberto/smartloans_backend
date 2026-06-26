from fastapi import APIRouter
from modules.clientDashboards import clientDashboards_sp, all_clientDashboards_sp


router = APIRouter()

with open("./docs_description/clientDashboards.txt", "r") as file:
    clientDashboards_docstring = file.read()
@router.post("/clientDashboards", summary="clientDashboards CRUD", description=clientDashboards_docstring)
def clientDashboards(json: dict):
    return clientDashboards_sp(json)


with open("./docs_description/clientDashboards_all.txt", "r") as file:
    clientDashboards_all_docstring = file.read()
@router.post("/all_clientDashboards", summary="all clientDashboards", description=clientDashboards_all_docstring)
def all_clientDashboards(json: dict):
    return all_clientDashboards_sp(json)
