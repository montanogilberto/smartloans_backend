import uuid
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from modules.mlJobs import ml_jobs_sp

router = APIRouter(prefix="", tags=["MercadoLibreJobs"])

@router.post("/mlJobs")
async def ml_jobs(request: Request):
    body = await request.json()
    req_id = request.headers.get("x-request-id") or str(uuid.uuid4())

    resp = ml_jobs_sp(body, request_id=req_id)
    resp.headers["x-request-id"] = req_id
    return resp