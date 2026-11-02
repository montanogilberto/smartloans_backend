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
import os
import re

import httpx

from fastapi.responses import JSONResponse

from databases import connection
from observability.integrations import timed_integration

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


def whatsapp_agent_dashboard(json_file: dict) -> JSONResponse:
    """POST /whatsapp/agentDashboard — the WhatsApp agent's activity and results
    for a company, read-only (sql/sp_whatsappAgentDashboard.sql)."""
    try:
        result = _sp("sp_whatsappAgentDashboard", json_file)
        status = 400 if isinstance(result, dict) and result.get("error") else 200
        return JSONResponse(result, status_code=status)
    except Exception as e:
        logger.exception("[whatsappAssistant] agent dashboard failed")
        return JSONResponse({"error": str(e)}, status_code=500)


def whatsapp_agent_conversations(json_file: dict) -> JSONResponse:
    """POST /whatsapp/agentConversations — what each customer wrote to the
    WhatsApp agent and its replies, for a company, read-only
    (sql/sp_whatsappAgentConversations.sql)."""
    try:
        result = _sp("sp_whatsappAgentConversations", json_file)
        status = 400 if isinstance(result, dict) and result.get("error") else 200
        return JSONResponse(result, status_code=status)
    except Exception as e:
        logger.exception("[whatsappAssistant] agent conversations failed")
        return JSONResponse({"error": str(e)}, status_code=500)


# LoanAgents_SmartLoans — the same service the WhatsApp agent runs on.
_AGENT_URL = os.environ.get("NEGOTIATION_AGENT_URL", "").rstrip("/")
_PHONE_RE = re.compile(r"\+?\d[\d\s().-]{7,}\d")
_EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")


def _strip_contact(text: str) -> str:
    return _EMAIL_RE.sub("[correo]", _PHONE_RE.sub("[teléfono]", text))


def whatsapp_agent_insights(json_file: dict) -> JSONResponse:
    """POST /whatsapp/agentInsights — "¿Qué quieren mis clientes?": the period's
    customer messages (sp_whatsappAgentConversations "messages", phones/emails
    stripped here) + topic counts go to LoanAgents /support/whatsapp-insights,
    which returns a summary, the common doubts with a suggestion, and unmet needs.
    Advisory and read-only: nothing is stored. Costs one LLM call per request."""
    row = (json_file.get("whatsappAgentInsights") or [{}])[0]
    company_id = row.get("companyId")
    start, end = row.get("startDate"), row.get("endDate")
    if not company_id or not start or not end:
        return JSONResponse({"error": "companyId, startDate and endDate are required"}, status_code=400)
    if not _AGENT_URL:
        return JSONResponse({"error": "NEGOTIATION_AGENT_URL is not set"}, status_code=503)
    try:
        found = _sp("sp_whatsappAgentConversations", {"whatsappAgentConversations": [
            {"action": "messages", "companyId": company_id, "startDate": start, "endDate": end}]})
        if found.get("error"):
            return JSONResponse({"error": found["error"]}, status_code=400)
        rows = (found.get("result") or [{}])[0].get("messages") or []
        counts: dict[str, int] = {}
        for r in rows:
            if r.get("topic"):
                counts[r["topic"]] = counts.get(r["topic"], 0) + 1
        body = {
            "companyId": company_id, "startDate": start, "endDate": end,
            "topicCounts": [{"topic": t, "count": n} for t, n in sorted(counts.items(), key=lambda x: -x[1])],
            "messages": [_strip_contact(r["message"]) for r in rows if r.get("message")],
        }
        # Request summary without the messages: the logs stay free of customer text.
        with timed_integration("loanagents_smartloans", "whatsapp_insights",
                               request={"companyId": company_id, "startDate": start, "endDate": end,
                                        "messages": len(body["messages"])},
                               company_id=company_id) as span:
            resp = httpx.post(f"{_AGENT_URL}/support/whatsapp-insights", json=body, timeout=60.0)
            span.http_status = resp.status_code
            resp.raise_for_status()
            data = resp.json()
        return JSONResponse({"result": [data]}, status_code=200)
    except Exception as e:
        logger.exception("[whatsappAssistant] agent insights failed")
        return JSONResponse({"error": str(e)}, status_code=502)
