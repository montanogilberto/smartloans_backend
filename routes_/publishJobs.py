from fastapi import APIRouter
from modules.publishJobs import publishJobs_sp


router = APIRouter()

# Read publishJobs  docstring from the file
with open("./docs_description/publishJobs.txt", "r") as file:
    publishJobs_docstring = file.read()
@router.post("/publishJobs",  summary="publishJobs CRUD", description=publishJobs_docstring)
def publishJobs(json: dict):
    return  publishJobs_sp(json)