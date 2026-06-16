from fastapi import APIRouter
from modules.clientFaceRecognitions import (
    clientFaceRecognitions_sp, all_clientFaceRecognitions_sp, one_clientFaceRecognitions_sp,
    verify_clientFaceRecognition_connector,
    contract_clientFaceRecognition_connector,
    create_azure_liveness_session,
)


router = APIRouter()

with open("./docs_description/clientFaceRecognitions.txt", "r") as file:
    clientFaceRecognitions_docstring = file.read()
@router.post("/clientFaceRecognitions", summary="clientFaceRecognitions CRUD", description=clientFaceRecognitions_docstring)
def clientFaceRecognitions(json: dict):
    return clientFaceRecognitions_sp(json)


with open("./docs_description/clientFaceRecognitions_all.txt", "r") as file:
    clientFaceRecognitions_all_docstring = file.read()
@router.post("/all_clientFaceRecognitions", summary="all clientFaceRecognitions", description=clientFaceRecognitions_all_docstring)
def all_clientFaceRecognitions(json: dict):
    return all_clientFaceRecognitions_sp(json)


with open("./docs_description/clientFaceRecognitions_one.txt", "r") as file:
    clientFaceRecognitions_one_docstring = file.read()
@router.post("/one_clientFaceRecognitions", summary="one clientFaceRecognition", description=clientFaceRecognitions_one_docstring)
def one_clientFaceRecognitions(json: dict):
    return one_clientFaceRecognitions_sp(json)


# --- connector routes (async) ---
@router.post("/api/clientFaceRecognition/create-session", summary="Create Azure Liveness Session", tags=["connector"])
async def create_liveness_session():
    return await create_azure_liveness_session()


@router.post("/api/clientFaceRecognition/verify", summary="Biometric verify ClientFaceRecognition", tags=["connector"])
async def verify_clientFaceRecognition(json: dict):
    return await verify_clientFaceRecognition_connector(json)


@router.post("/api/clientFaceRecognition/contract", summary="Submit contract ClientFaceRecognition", tags=["connector"])
async def contract_clientFaceRecognition(json: dict):
    return await contract_clientFaceRecognition_connector(json)
