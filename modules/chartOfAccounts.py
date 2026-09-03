"""
Chart of accounts (Catálogo de Cuentas) — the account tree every
journalEntry line posts against. Módulo Contabilidad.

Spec: posgmo-factory/tests/prd_chartOfAccount.json
"""

import json
from fastapi.responses import JSONResponse
from databases import connection


def _conn():
    return connection()


def _sp(proc: str, json_file: dict):
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{proc}] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


def chart_of_accounts_sp(json_file: dict):
    """CRUD passthrough (sp_chartOfAccounts). action 1=create, 2=update, 3=deactivate."""
    try:
        return JSONResponse(_sp("sp_chartOfAccounts", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def all_chart_of_accounts_sp(json_file: dict):
    try:
        return JSONResponse(_sp("sp_chartOfAccounts_all", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def one_chart_of_account_sp(json_file: dict):
    try:
        return JSONResponse(_sp("sp_chartOfAccounts_one", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
