from fastapi.responses import JSONResponse
from databases import connection
import json


def payment_history_all_sp(json_file: dict):
    """Read-only audit trail (D16) — see sql/sp_fundingTransactions.sql's
    paymentHistory table + sp_paymentHistory_all."""
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_paymentHistory_all] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        row = cursor.fetchone()
        json_result = row[0] if row and row[0] else "[]"
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
