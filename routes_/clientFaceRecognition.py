from fastapi import APIRouter
from modules.clientFaceRecognitions import (
    clientFaceRecognitions_sp, all_clientFaceRecognitions_sp, one_clientFaceRecognitions_sp,
    contract_clientFaceRecognition_connector,
    upload_id_image_connector,
    upload_presence_capture_connector,
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
@router.post("/api/clientFaceRecognition/upload-image", summary="Upload a single ID/selfie image", tags=["connector"])
async def upload_id_image(json: dict):
    return await upload_id_image_connector(json)


@router.post("/api/clientFaceRecognition/contract", summary="Submit contract ClientFaceRecognition", tags=["connector"])
async def contract_clientFaceRecognition(json: dict):
    return await contract_clientFaceRecognition_connector(json)


@router.post("/api/clientFaceRecognition/upload-presence", summary="Upload a presence (video) capture", tags=["connector"])
async def upload_presence_capture(json: dict):
    return await upload_presence_capture_connector(json)
