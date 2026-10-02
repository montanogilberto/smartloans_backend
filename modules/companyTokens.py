"""Company AI-token ledger: record agent usage, top up, read the balance.

Thin wrapper over sp_companyTokens_* (sql/migrations/2026-10-02c_company_token_ledger.sql).
The balance is the SUM of an append-only ledger; this module never edits rows.
"""
import json

from fastapi.responses import JSONResponse

from databases import connection


def _call_sp(sp_name: str, payload: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{sp_name}] @pjsonfile = %s", (json.dumps(payload),))
        rows = cursor.fetchall()
        raw = "".join(row[0] for row in rows if row and row[0])
        conn.commit()
        result = json.loads(raw) if raw else {}
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def company_tokens_balance_sp(json_file: dict):
    return _call_sp("sp_companyTokens_balance", json_file)


def company_tokens_record_sp(json_file: dict):
    return _call_sp("sp_companyTokens_record", json_file)


def company_tokens_topup_sp(json_file: dict):
    return _call_sp("sp_companyTokens_topup", json_file)
