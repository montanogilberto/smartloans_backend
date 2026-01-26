import json
import uuid
import logging
from fastapi.responses import JSONResponse
from databases import connection

logger = logging.getLogger("mlJobs")
conn = connection()

def ml_jobs_sp(json_file: dict, request_id: str | None = None):
    req_id = request_id or str(uuid.uuid4())

    # Safe log
    try:
        action = None
        jt = None
        if isinstance(json_file, dict):
            jb = (json_file.get("jobs") or [{}])[0]
            action = jb.get("action")
            jt = jb.get("job_type")
        logger.info(f"[{req_id}] ml_jobs_sp action={action} job_type={jt}")
    except Exception:
        logger.info(f"[{req_id}] ml_jobs_sp called (log parse failed)")

    try:
        cursor = conn.cursor()
        cursor.execute("EXEC dbo.sp_ml_jobs @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        output_json_str = rows[0][1] if rows and len(rows[0]) > 1 else None
        if output_json_str is None:
            return JSONResponse(content={"error": "Empty SP response"}, status_code=500)

        return JSONResponse(content=json.loads(output_json_str), status_code=200)

    except Exception as e:
        logger.exception(f"[{req_id}] ml_jobs_sp error")
        return JSONResponse(content={"error": str(e), "request_id": req_id}, status_code=500)
