from fastapi import APIRouter
from modules.mlJobs import mlJobs_sp

router = APIRouter()

with open("./docs_description/mlJobs.txt", "r") as file:
    mlJobs_docstring = file.read()

@router.post("/mlJobs", summary="ML Jobs Queue CRUD", description=mlJobs_docstring)
def mlJobs(json: dict):
    return mlJobs_sp(json)
