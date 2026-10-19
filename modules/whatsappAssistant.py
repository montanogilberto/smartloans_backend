"""
Content the WhatsApp assistant answers from (LoanAgents_SmartLoans
agents/whatsapp_reservations): promotions, business info, FAQs — each
company edits its own from the POS — plus the sender's own reward points.

Promotions are the coupons in dbo.posRewardCatalogItems (sql/sp_promotions.sql);
that SP and sp_whatsappCustomerRewards are deployed directly in the database with
the POS rewards objects (sql/migrations/README_pos_rewards.md).

All DB access through SPs (sql/sp_promotions.sql, sp_businessInfo.sql,
sp_businessFaqs.sql, sp_whatsappCustomerRewards.sql), deployed directly in the
database: run order in sql/migrations/README_whatsapp_assistant.md.
"""

import json
import logging

from fastapi.responses import JSONResponse

from databases import connection

logger = logging.getLogger(__name__)

_PROCEDURES = {
    "promotions": "sp_promotions",
    "businessInfo": "sp_businessInfo",
    "businessFaqs": "sp_businessFaqs",
}


def _sp(procedure: str, json_file: dict) -> dict:
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{procedure}] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


def assistant_catalog_sp(key: str, json_file: dict) -> JSONResponse:
    """Passthrough for /promotions, /businessInfo, /businessFaqs."""
    procedure = _PROCEDURES[key]
    try:
        return JSONResponse(_sp(procedure, json_file), status_code=200)
    except Exception as e:
        logger.exception("[whatsappAssistant] %s failed", procedure)
        return JSONResponse({"error": str(e)}, status_code=500)


def customer_rewards(json_file: dict) -> JSONResponse:
    """The WhatsApp sender's own points (sp_whatsappCustomerRewards). The
    route requires the worker key: the phone comes from the agent service,
    which takes it from Meta's webhook — never from what the customer types."""
    try:
        return JSONResponse(_sp("sp_whatsappCustomerRewards", json_file), status_code=200)
    except Exception as e:
        logger.exception("[whatsappAssistant] customer rewards failed")
        return JSONResponse({"error": str(e)}, status_code=500)
