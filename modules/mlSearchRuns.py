import json
import uuid
import logging
from fastapi.responses import JSONResponse
from databases import connection

logger = logging.getLogger("mlSearchRuns")

def ml_search_runs_sp(json_file: dict, request_id: str | None = None):
    req_id = request_id or str(uuid.uuid4())

    # Safe log
    try:
        sr = (json_file.get("search_runs") or [{}])[0] if isinstance(json_file, dict) else {}
        logger.info("[%s] ml_search_runs_sp action=%s status=%s http_status=%s",
                    req_id, sr.get("action"), sr.get("status"), sr.get("http_status"))
    except Exception:
        logger.info("[%s] ml_search_runs_sp called (log parse failed)", req_id)

    conn = None
    cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()

        cursor.execute("EXEC dbo.sp_ml_search_runs @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()

        try:
            conn.commit()
        except Exception:
            pass

        output_json_str = rows[0][1] if rows and len(rows[0]) > 1 else None
        if not output_json_str:
            return JSONResponse(content={"error": "Empty SP response", "request_id": req_id}, status_code=500)

        return JSONResponse(content=json.loads(output_json_str), status_code=200)

    except Exception as e:
        logger.exception("[%s] ml_search_runs_sp error", req_id)
        return JSONResponse(content={"error": str(e), "request_id": req_id}, status_code=500)

    finally:
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass
        try:
            if conn:
                conn.close()
        except Exception:
            pass
