from fastapi import APIRouter
from modules.messageTickets import messageTickets_sp


router = APIRouter()

# Read messageTickets  docstring from the file
with open("./docs_description/messageTickets.txt", "r") as file:
    messageTickets_docstring = file.read()
@router.post("/messageTickets",  summary="messageTickets CRUD", description=messageTickets_docstring)
def messageTickets(json: dict):
    return  messageTickets_sp(json)