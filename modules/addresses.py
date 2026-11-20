"""
Client addresses by source (dbo.addresses): "ine" (as printed on the INE, or as
the person corrected it) and "gps" (reverse-geocoded presence capture), one
active row each per client. See sql/migrations/2026-11-20_addresses_kyc_sources.sql.

Written by hand: the posgmo-factory couldn't reuse the 2024 dbo.addresses table.
Addresses are personal data — never logged (errors log only ids and the SP's message).
"""
import json
import logging

from fastapi.responses import JSONResponse

from databases import connection

_KEY = "addresses"
logger = logging.getLogger("addresses")


def _one_row(json_file: dict):
    rows = json_file.get(_KEY) if isinstance(json_file, dict) else None
    if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
        return None
    return rows[0]


def _read_json(procedure: str, json_file: dict) -> dict:
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{procedure}] @pjsonfile = %s", (json.dumps(json_file),))
        raw = "".join(r[0] for r in cursor.fetchall() if r and r[0])
        return json.loads(raw) if raw else {_KEY: []}
    finally:
        if conn:
            conn.close()


def addresses_sp(json_file: dict):
    """{"addresses": [{action 1 (upsert by companyId+clientId+source) | 3 (deactivate), ...}]}"""
    row = _one_row(json_file)
    if row is None:
        return JSONResponse(content={"error": f"{_KEY} must hold exactly one row"}, status_code=400)

    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_addresses] @pjsonfile = %s", (json.dumps({_KEY: [row]}),))
        result = cursor.fetchone()
        value, msg, error = (list(result) + [None, None, None])[:3] if result else ("", "", "1")
    except Exception as e:
        logger.error("[addresses] sp_addresses failed clientId=%s: %s", row.get("clientId"), type(e).__name__)
        return JSONResponse(content={"error": "No se pudo guardar el domicilio"}, status_code=500)
    finally:
        if conn:
            conn.close()

    if error:
        return JSONResponse(content={"status": "error", "message": msg or "Error"}, status_code=400)
    address_id = int(value) if str(value or "").isdigit() else ""
    return JSONResponse(content={"status": "success", "message": msg or "", "value": address_id}, status_code=200)


def client_addresses_sp(json_file: dict):
    """{"addresses": [{"companyId", "clientId"}]} -> active rows of that client."""
    row = _one_row(json_file)
    if row is None:
        return JSONResponse(content={"error": f"{_KEY} must hold exactly one row"}, status_code=400)
    try:
        return JSONResponse(content=_read_json("sp_addresses_all", {_KEY: [row]}), status_code=200)
    except Exception as e:
        logger.error("[addresses] sp_addresses_all failed clientId=%s: %s", row.get("clientId"), type(e).__name__)
        return JSONResponse(content={"error": "No se pudieron leer los domicilios"}, status_code=500)


def one_address_sp(json_file: dict):
    """{"addresses": [{"companyId", "clientId", "addressId"}]} -> that row."""
    row = _one_row(json_file)
    if row is None:
        return JSONResponse(content={"error": f"{_KEY} must hold exactly one row"}, status_code=400)
    try:
        return JSONResponse(content=_read_json("sp_addresses_one", {_KEY: [row]}), status_code=200)
    except Exception as e:
        logger.error("[addresses] sp_addresses_one failed addressId=%s: %s", row.get("addressId"), type(e).__name__)
        return JSONResponse(content={"error": "No se pudo leer el domicilio"}, status_code=500)
