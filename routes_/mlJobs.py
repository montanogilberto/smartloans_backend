import uuid
from fastapi import APIRouter, Request
from modules.mlJobs import ml_jobs_sp

router = APIRouter(prefix="", tags=["MercadoLibreJobs"])

@router.post("/mlJobs")
async def ml_jobs(request: Request):
    body = await request.json()
    req_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    return ml_jobs_sp(body, request_id=req_id)
