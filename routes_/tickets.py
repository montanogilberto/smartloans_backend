
from fastapi import APIRouter
from modules.tickets import one_tickets_sp

router = APIRouter()

# Read one ticket docstring from the file
with open("./docs_description/tickets_one.txt", "r") as file:
    ticket_one_docstring = file.read()
@router.post("/one_tickets",  summary="one ticket", description=ticket_one_docstring)
def one_tickets(json: dict):
    return  one_tickets_sp(json)
