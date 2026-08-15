from fastapi.responses import JSONResponse
from databases import connection
import json


def _conn():
    return connection()


def funding_transactions_sp(json_file: dict):
    """declare | confirm | reject | escalate_due | resolve_escalation | list | one
    via sp_fundingTransactions. See sql/sp_fundingTransactions.sql — the
    lender declares a SPEI they already sent from their own bank, the
    borrower confirms or rejects; SmartLoans never initiates or moves the
    transfer itself (D5: never auto-confirm)."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_fundingTransactions] @pjsonfile = %s",
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
