from fastapi.responses import JSONResponse
from databases import connection
import json


def _conn():
    return connection()


def payment_intents_sp(json_file: dict):
    """create | expire_due | cancel | list via sp_paymentIntents.
    See sql/sp_paymentIntents.sql for the non-custodial boundary note —
    this table only ever records the EXPECTATION of a direct SPEI transfer,
    never moves money itself."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_paymentIntents] @pjsonfile = %s",
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
