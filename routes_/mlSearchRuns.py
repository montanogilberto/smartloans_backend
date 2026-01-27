import uuid
from fastapi import APIRouter, Request
from modules.mlSearchRuns import ml_search_runs_sp

router = APIRouter(prefix="", tags=["MercadoLibreSearchRuns"])

@router.post("/mlSearchRuns")
async def ml_search_runs(request: Request):
    body = await request.json()
    req_id = request.headers.get("x-request-id") or str(uuid.uuid4())

    resp = ml_search_runs_sp(body, request_id=req_id)
    resp.headers["x-request-id"] = req_id
    return resp
