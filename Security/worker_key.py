# security/worker_key.py
import os
from fastapi import Header, HTTPException

WORKER_KEY = os.getenv("WORKER_KEY", "")

def require_worker_key(x_worker_key: str | None = Header(default=None)):
    if not WORKER_KEY or x_worker_key != WORKER_KEY:
        raise HTTPException(status_code=403, detail="Forbidden")
