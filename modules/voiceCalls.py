"""
POST /voiceCalls/place — a POS user asks the virtual Secretary to phone a client.

The Secretary itself runs in LoanAgents_SmartLoans (voice/twilio_bridge.py): this
backend only places the call. It asks Twilio to dial the client and connect the
audio to VOICE_STREAM_URL (the LoanAgents /voice/twilio-stream WebSocket), passing
a signed call token as a <Stream> <Parameter>. The token is the only way trusted
values (company, client, the name the agent says) reach the call; its format must
stay identical to LoanAgents' voice/call_token.py, signed with the same
VOICE_CALL_SECRET.

The phone dialed is the client's own cellphone from the database, never one sent
by the app, so the call and the client it talks about can't disagree.

Nothing here touches money. Logs carry clientId and the Twilio call SID only —
never the phone number or the token.

Env:
  VOICE_CALLS_ENABLED=1        off by default: a real phone rings
  TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN
  TWILIO_VOICE_FROM            caller ID (E.164): a Twilio number or Verified Caller ID
  VOICE_CALL_SECRET            same value as the LoanAgents app
  VOICE_STREAM_URL             wss://<loanagents host>/voice/twilio-stream
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import re
import time
from xml.sax.saxutils import quoteattr

import httpx
from fastapi.responses import JSONResponse

from modules.clients import one_clients_sp
from modules.companies import company_name
from observability.integrations import timed_integration
from observability.logger import log_workflow_step

logger = logging.getLogger(__name__)

# The POS "mostrador" placeholder for anonymous sales: it has a real phone on
# file, so a call for it would ring a stranger. Same id as LoanAgents.
WALK_IN_CLIENT_ID = 1
TOKEN_TTL_S = 10 * 60   # minted right before Twilio dials; LoanAgents caps it at 15 min
_TWILIO_CALLS = "https://api.twilio.com/2010-04-01/Accounts/{sid}/Calls.json"


def _error(code: str, status: int) -> JSONResponse:
    return JSONResponse(content={"placed": False, "error": code}, status_code=status)


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def sign_call_token(payload: dict, secret: str, ttl_s: int = TOKEN_TTL_S, now: float | None = None) -> str:
    """base64url(json payload) "." base64url(HMAC-SHA256) — LoanAgents' format."""
    if not secret:
        raise ValueError("VOICE_CALL_SECRET is not set")
    issued = int(now if now is not None else time.time())
    body = _b64(json.dumps({**payload, "exp": issued + ttl_s},
                           separators=(",", ":"), ensure_ascii=False).encode())
    sig = _b64(hmac.new(secret.encode(), body.encode("ascii"), hashlib.sha256).digest())
    return f"{body}.{sig}"


def to_e164_mx(cellphone: object) -> str:
    """'6621234567' / '526621234567' / '+52 662 123 4567' → '+526621234567'; '' if not a MX mobile."""
    digits = re.sub(r"\D", "", str(cellphone or ""))
    if len(digits) == 13 and digits.startswith("521"):   # old WhatsApp-style 521 prefix
        digits = "52" + digits[3:]
    if len(digits) == 10:
        return "+52" + digits
    if len(digits) == 12 and digits.startswith("52"):
        return "+" + digits
    return ""


def _config() -> dict | None:
    cfg = {
        "sid": os.getenv("TWILIO_ACCOUNT_SID", ""),
        "auth": os.getenv("TWILIO_AUTH_TOKEN", ""),
        "from": os.getenv("TWILIO_VOICE_FROM", ""),
        "secret": os.getenv("VOICE_CALL_SECRET", ""),
        "stream": os.getenv("VOICE_STREAM_URL", ""),
    }
    return cfg if all(cfg.values()) and cfg["stream"].startswith("wss://") else None


def _find_client(client_id: int) -> dict:
    resp = one_clients_sp({"clients": [{"clientId": client_id}]})
    try:
        data = json.loads(resp.body)
    except (TypeError, ValueError):
        return {}
    rows = data.get("clients") if isinstance(data, dict) else None
    return rows[0] if isinstance(rows, list) and rows and isinstance(rows[0], dict) else {}


def place_call(json_file: dict) -> JSONResponse:
    """json_file = {"voiceCall": [{"companyId", "clientId", "userId"}]} — authorization
    (a staff session of that company) is checked by the route before this runs."""
    rows = json_file.get("voiceCall") if isinstance(json_file, dict) else None
    row = rows[0] if isinstance(rows, list) and rows and isinstance(rows[0], dict) else {}
    try:
        company_id, client_id = int(row.get("companyId")), int(row.get("clientId"))
    except (TypeError, ValueError):
        return _error("invalid", 400)

    if os.getenv("VOICE_CALLS_ENABLED", "").strip() != "1":
        return _error("disabled", 503)
    cfg = _config()
    if cfg is None:
        logger.warning("[voiceCalls] not configured: TWILIO_* / TWILIO_VOICE_FROM / VOICE_CALL_SECRET / VOICE_STREAM_URL")
        return _error("not_configured", 503)
    if client_id == WALK_IN_CLIENT_ID:
        return _error("walk_in", 400)

    client = _find_client(client_id)
    try:
        client_company = int(client.get("companyId"))
    except (TypeError, ValueError):
        client_company = None
    if client_company != company_id:
        return _error("not_found", 404)
    to = to_e164_mx(client.get("cellphone"))
    if not to:
        return _error("no_phone", 400)
    if to == to_e164_mx(cfg["from"]) or to == cfg["from"]:
        return _error("no_phone", 400)

    token = sign_call_token({
        "companyId": company_id, "branchId": None, "clientId": client_id, "orderId": None,
        "companyName": company_name({"companyId": company_id}) or None,
        "customerName": (str(client.get("first_name") or "").strip() or None),
        # The Secretary's "your order is ready" script; no order details yet
        # (there's no company-scoped "latest open order" lookup).
        "order": {"service": None, "total": None},
    }, cfg["secret"])
    twiml = (f'<Response><Connect><Stream url={quoteattr(cfg["stream"])}>'
             f'<Parameter name="token" value={quoteattr(token)}/></Stream></Connect></Response>')

    try:
        with timed_integration("twilio_voice", "place_call", company_id=company_id,
                               request={"clientId": client_id}) as span:
            resp = httpx.post(_TWILIO_CALLS.format(sid=cfg["sid"]), auth=(cfg["sid"], cfg["auth"]),
                              data={"To": to, "From": cfg["from"], "Twiml": twiml}, timeout=15.0)
            span.http_status = resp.status_code
            resp.raise_for_status()
            call = resp.json()
    except Exception as exc:  # noqa: BLE001 — Twilio refused or unreachable
        logger.error("[voiceCalls] Twilio refused the call for client %s: %s", client_id, type(exc).__name__)
        log_workflow_step("voice_call_place", action="place", status="FAILED", workflow_name="voice_secretary",
                          entity="client", entity_id=client_id, message=type(exc).__name__)
        return _error("call_failed", 502)

    call_sid = call.get("sid") if isinstance(call, dict) else None
    # "queued" = Twilio accepted it, not that the client answered.
    log_workflow_step("voice_call_place", action="place", workflow_name="voice_secretary",
                      entity="client", entity_id=client_id, message=f"callSid={call_sid} userId={row.get('userId')}")
    return JSONResponse(content={"placed": True, "callSid": call_sid,
                                 "status": call.get("status") if isinstance(call, dict) else None},
                        status_code=200)
