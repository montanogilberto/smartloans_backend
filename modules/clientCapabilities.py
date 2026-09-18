"""
clientCapabilities — the multi-valued "clientTypes" concept: which GMO
applications/capabilities a dbo.clients row participates in (POS,
SmartLoans Lender/Borrower/Juridical, Rewards, Arcade). A client may hold
any combination.

Deliberately separate from dbo.clients.clientType (singular, pre-existing,
lending-role label) -- that column and every page reading it are untouched.
This module does not read, write, or derive from clientType.

Spec: sql/sp_clientCapabilities.sql
Not an authorization mechanism by itself -- see routes_/clientCapabilities.py.
"""

import json
from fastapi.responses import JSONResponse
from databases import connection


def _sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_clientCapabilities] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


def _crud_status(result: dict) -> int:
    try:
        row = result.get("result", [{}])[0]
        return 400 if str(row.get("error") or "") == "1" else 200
    except Exception:
        return 200


def client_capabilities_sp(json_file: dict):
    """CRUD passthrough (sp_clientCapabilities). action 0=read, 1=grant, 2=revoke."""
    try:
        result = _sp(json_file)
        return JSONResponse(result, status_code=_crud_status(result))
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
