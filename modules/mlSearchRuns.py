import json
import uuid
import logging
from fastapi.responses import JSONResponse
from databases import connection

logger = logging.getLogger("mlSearchRuns")
conn = connection()

def ml_search_runs_sp(json_file: dict, request_id: str | None = None):
    req_id = request_id or str(uuid.uuid4())

    # Safe log (no secrets)
    try:
        action = None
        if isinstance(json_file, dict):
            sr = (json_file.get("search_runs") or [{}])[0]
            action = sr.get("action")
        logger.info(f"[{req_id}] ml_search_runs_sp action={action}")
    except Exception:
        logger.info(f"[{req_id}] ml_search_runs_sp called (log parse failed)")

    try:
        cursor = conn.cursor()
        cursor.execute("EXEC dbo.sp_ml_search_runs @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()

        # Your standard: json string is at [0][1]
        output_json_str = rows[0][1] if rows and len(rows[0]) > 1 else None
        if output_json_str is None:
            return JSONResponse(content={"error": "Empty SP response"}, status_code=500)

        # Return as parsed JSON object (recommended)
        return JSONResponse(content=json.loads(output_json_str), status_code=200)

    except Exception as e:
        logger.exception(f"[{req_id}] ml_search_runs_sp error")
        return JSONResponse(content={"error": str(e), "request_id": req_id}, status_code=500)
