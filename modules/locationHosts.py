"""
Red GMO — businesses offering space for a GMO locker (host candidates).

PRD posgmo-factory tests/prd_locationHost.json (2026-11-10). The factory run
failed SQL validation, so this module and its SQL are hand-written on the
demandSignals pattern. Rows are written ONLY from the WhatsApp agent path
(modules/whatsappReservations, RECORD_LOCATION_HOST) through
record_location_host(); staff only change the pipeline status. There is no
public create/delete route. The host's commission and weekly payout are NOT
here: they need a payments RFC.
"""

import json

from fastapi.responses import JSONResponse

from databases import connection
from observability.logger import workflow_step


def _exec(procedure: str, json_file: dict) -> dict:
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{procedure}] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        # SQL Server may split long JSON across rows: always join.
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {"error": "empty response"}
    finally:
        if conn:
            conn.close()


def record_location_host(json_file: dict) -> dict:
    """Upsert one host candidate: {"locationHosts": [{companyId, channelId,
    contactPhone, businessName, ...}]}. companyId, channelId and contactPhone
    must come from the WhatsApp channel and sender. Returns {"locationHostId",
    "status"}. Raises on failure; workflow_step logs it."""
    with workflow_step("record_location_host", workflow_name="client_acquisition",
                       entity="locationHost", action="upsert"):
        result = _exec("sp_locationHosts", json_file)
        if result.get("error"):
            raise RuntimeError(f"sp_locationHosts: {result['error']}")
        return result["result"][0]


def _respond(procedure: str, json_file: dict) -> JSONResponse:
    try:
        content = _exec(procedure, json_file)
        return JSONResponse(content=content, status_code=400 if "error" in content else 200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def all_locationHosts_sp(json_file: dict) -> JSONResponse:
    return _respond("sp_locationHosts_all", json_file)


def status_locationHosts_sp(json_file: dict) -> JSONResponse:
    with workflow_step("location_host_status", workflow_name="client_acquisition",
                       entity="locationHost", action="update"):
        return _respond("sp_locationHosts_status", json_file)
