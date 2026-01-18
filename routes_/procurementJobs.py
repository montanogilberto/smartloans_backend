from fastapi import APIRouter
from modules.procurementJobs import procurementJob_sp


router = APIRouter()

# Read procurementJobs  docstring from the file
with open("./docs_description/procurementJobs.txt", "r") as file:
    procurementJobs_docstring = file.read()
@router.post("/procurementJobs",  summary="procurementJobs CRUD", description=procurementJobs_docstring)
def procurementJobs(json: dict):
    return  procurementJob_sp(json)