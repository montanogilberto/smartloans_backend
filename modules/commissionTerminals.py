"""
commission_terminals — catalog of card/payment terminals and their
negotiated commission rate (e.g. Mercado Pago @ 4.2%). income.commissionTerminalId
points here. Global catalog, not company-scoped.

Spec: sql/sp_commissionTerminals.sql
"""

import json
from fastapi.responses import JSONResponse
from databases import connection


def _sp(proc: str, json_file: dict | None = None):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        if json_file is not None:
            cursor.execute(f"EXEC [dbo].[{proc}] @pjsonfile = %s", (json.dumps(json_file),))
        else:
            cursor.execute(f"EXEC [dbo].[{proc}]")
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


def commission_terminals_sp(json_file: dict):
    """CRUD passthrough (sp_commissionTerminals). action 1=create, 2=update, 3=deactivate."""
    try:
        return JSONResponse(_sp("sp_commissionTerminals", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def all_commission_terminals_sp():
    try:
        return JSONResponse(_sp("sp_commissionTerminals_all"), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def one_commission_terminal_sp(json_file: dict):
    try:
        return JSONResponse(_sp("sp_commissionTerminals_one", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
