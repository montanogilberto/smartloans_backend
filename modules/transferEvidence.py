from fastapi.responses import JSONResponse
from databases import connection
import json


def _conn():
    return connection()


def transfer_evidence_sp(json_file: dict):
    """create | list | one via sp_transferEvidence. Stores PROOF a direct
    SPEI transfer happened outside SmartLoans (clave de rastreo, bank,
    optional attachment + hash) -- see sql/sp_transferEvidence.sql. Never
    moves money itself."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_transferEvidence] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        row = cursor.fetchone()
        json_result = row[0] if row and row[0] else '{"error":"no result"}'
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
