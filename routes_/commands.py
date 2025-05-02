from fastapi import APIRouter
from modules.commands import all_commands_sp


router = APIRouter()

# Read all checks docstring from the file
with open("./docs_description/commands_all.txt", "r") as file:
    commands_all_docstring = file.read()
@router.get("/all_commands",  summary="all commands", description=commands_all_docstring)
def all_commands():
    return  all_commands_sp()