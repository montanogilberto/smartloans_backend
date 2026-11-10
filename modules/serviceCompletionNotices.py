"""
"Tu servicio está listo" — staff tell the customer of a POS sale that the
service they paid for is finished (Dashboard → Actividad Reciente).

Only for companies that switched the SERVICE_COMPLETION_NOTICE feature on in
dbo.companyFeatures (factory module companyFeature). No row, a disabled row or
an unreadable table = OFF: a grocery store never sees the action, and the
frontend never decides it from a companyId.

SERVICE_COMPLETED is its own business event (eventName service_completed),
not income_created: the sale is the money, this is the operation. Sending
goes through the existing push → WhatsApp → SMS cascade
(notificationDispatch), which records every attempt in notificationDispatches
and refuses to re-send once one is sent/confirmed for (company, 'income',
incomeId, service_completed) — a double click never texts the client twice,
and a failed attempt can be retried.

Hand-written orchestration over existing tables (no table of its own), like
voiceCalls.
"""
from __future__ import annotations

import json
import logging

from fastapi.responses import JSONResponse

from databases import connection
from modules.clients import one_clients_sp
from modules.companies import company_name
from observability import log_workflow_step

logger = logging.getLogger(__name__)

FEATURE_KEY = "SERVICE_COMPLETION_NOTICE"
ACTION_KEY = "NOTIFY_SERVICE_COMPLETION"
EVENT = "service_completed"
SOURCE_TYPE = "income"
WALK_IN_CLIENT_ID = 1
MAX_STATUS_IDS = 30

DEFAULTS = {
    "waTemplate": "servicio_listo",
    "pushTitle": "Tu servicio está listo",
    "navigationRoute": "/my-qr",
}


def _error(code: str, status: int) -> JSONResponse:
    return JSONResponse({"error": code}, status_code=status)


def _sp_rows(cursor, sp: str, key: str, row: dict) -> list:
    """EXEC an @pjsonfile SP and return its `key` rows ([] when none)."""
    cursor.execute(f"EXEC {sp} @pjsonfile = %s", (json.dumps({key: [row]}),))
    rows = cursor.fetchall()
    text = "".join((r[0] or "") for r in rows).strip() if rows else ""
    if not text:
        return []
    parsed = json.loads(text)
    if isinstance(parsed, dict) and parsed.get("error"):
        raise RuntimeError(f"{sp}: {parsed['error']}")
    if isinstance(parsed, dict):
        found = parsed.get(key)
        if found is None and isinstance(parsed.get("result"), list):
            found = parsed["result"]
        return found if isinstance(found, list) else []
    return parsed if isinstance(parsed, list) else []


def feature_config(company_id: int) -> dict | None:
    """The company's config for this feature, or None when it is off. Any
    failure reading it (table not deployed yet, DB error) also means off."""
    conn = None
    try:
        conn = connection()
        rows = _sp_rows(conn.cursor(), "sp_companyFeatures_one", "companyFeatures",
                        {"companyId": company_id, "featureKey": FEATURE_KEY})
    except Exception:
        logger.exception("[serviceCompletion] feature lookup failed company=%s — treating as off", company_id)
        return None
    finally:
        if conn:
            conn.close()
    row = rows[0] if rows and isinstance(rows[0], dict) else None
    if not row or not row.get("enabled") or str(row.get("enabled")).lower() in ("0", "false"):
        return None
    try:
        extra = json.loads(row["configJson"]) if row.get("configJson") else {}
    except (TypeError, ValueError):
        logger.warning("[serviceCompletion] invalid configJson company=%s — using defaults", company_id)
        extra = {}
    return {**DEFAULTS, **(extra if isinstance(extra, dict) else {})}


def _income(cursor, company_id: int, income_id: int) -> dict | None:
    rows = _sp_rows(cursor, "sp_income_one", "income", {"incomeId": income_id, "companyId": company_id})
    row = rows[0] if rows and isinstance(rows[0], dict) else None
    # The SP filters by company; check again so another company's sale is never touched.
    if not row or int(row.get("companyId") or 0) != company_id:
        return None
    return row


def _sent(cursor, company_id: int, income_id: int) -> dict | None:
    """The sent/confirmed dispatch for this sale, or None."""
    from modules.notificationDispatch import _lookup  # lazy: heavy module
    rows = _lookup(cursor, {"action": "resolved", "companyId": company_id, "sourceType": SOURCE_TYPE,
                            "sourceId": income_id, "eventName": EVENT})
    return rows[0] if rows else None


def _client(client_id: int) -> dict:
    resp = one_clients_sp({"clients": [{"clientId": client_id}]})
    try:
        data = json.loads(resp.body)
    except (TypeError, ValueError):
        return {}
    rows = data.get("clients") if isinstance(data, dict) else None
    return rows[0] if isinstance(rows, list) and rows and isinstance(rows[0], dict) else {}


def _eligible_client(income: dict) -> int | None:
    try:
        client_id = int(income.get("clientId") or 0)
    except (TypeError, ValueError):
        return None
    return client_id if client_id and client_id != WALK_IN_CLIENT_ID else None


def _ids(json_file: dict, key: str) -> tuple[int, int, dict] | None:
    rows = json_file.get(key)
    row = rows[0] if isinstance(rows, list) and len(rows) == 1 and isinstance(rows[0], dict) else None
    if row is None:
        return None
    try:
        return int(row["companyId"]), int(row["userId"]), row
    except (KeyError, TypeError, ValueError):
        return None


def message(first_name: str, company: str) -> str:
    """The push/SMS text; WhatsApp sends the same words through servicio_listo."""
    hello = f"¡Hola, {first_name}!" if first_name else "¡Hola!"
    where = f" en {company}" if company else ""
    return f"{hello} Tu servicio{where} está listo. Ya puedes pasar por tu pedido. ¡Gracias por tu preferencia!"


def status(json_file: dict) -> JSONResponse:
    """POST /serviceCompletionNotices/status
    Body {"serviceCompletionNotices": [{companyId, userId, incomeIds: [int, ...]}]}
    → {enabled, actions: {incomeId: {key, status: available|sent, channel?, sentAt?}}}.
    A sale missing from `actions` has no action (walk-in, another company, or
    the feature is off — then `actions` is empty and no sale is read)."""
    ids = _ids(json_file, "serviceCompletionNotices")
    if ids is None:
        return _error("invalid", 400)
    company_id, _user_id, row = ids
    raw = row.get("incomeIds")
    if not isinstance(raw, list):
        return _error("invalid", 400)
    try:
        income_ids = list(dict.fromkeys(int(i) for i in raw))[:MAX_STATUS_IDS]
    except (TypeError, ValueError):
        return _error("invalid", 400)

    if feature_config(company_id) is None:
        return JSONResponse({"enabled": False, "actions": {}}, status_code=200)

    actions: dict = {}
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        for income_id in income_ids:
            income = _income(cursor, company_id, income_id)
            if not income or _eligible_client(income) is None:
                continue
            sent = _sent(cursor, company_id, income_id)
            actions[str(income_id)] = (
                {"key": ACTION_KEY, "status": "sent", "channel": sent.get("selectedChannel"),
                 "sentAt": sent.get("sentAt")}
                if sent else {"key": ACTION_KEY, "status": "available"})
    except Exception:
        logger.exception("[serviceCompletion] status failed company=%s", company_id)
        return _error("status_failed", 500)
    finally:
        if conn:
            conn.close()
    return JSONResponse({"enabled": True, "actions": actions}, status_code=200)


async def send(json_file: dict) -> JSONResponse:
    """POST /serviceCompletionNotices/send
    Body {"serviceCompletionNotice": [{companyId, userId, incomeId}]}
    200 {status: sent|already_sent, channel, attempted}   403 feature_disabled
    404 not_found (no such sale in this company)   409 no_client (walk-in / no client)
    502 send_failed (every channel failed; it can be retried)."""
    ids = _ids(json_file, "serviceCompletionNotice")
    if ids is None:
        return _error("invalid", 400)
    company_id, user_id, row = ids
    try:
        income_id = int(row["incomeId"])
    except (KeyError, TypeError, ValueError):
        return _error("invalid", 400)

    config = feature_config(company_id)
    if config is None:
        return _error("feature_disabled", 403)

    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        income = _income(cursor, company_id, income_id)
        if income is None:
            return _error("not_found", 404)
        client_id = _eligible_client(income)
        if client_id is None:
            return _error("no_client", 409)
        sent = _sent(cursor, company_id, income_id)
    except Exception:
        logger.exception("[serviceCompletion] lookup failed company=%s income=%s", company_id, income_id)
        return _error("send_failed", 502)
    finally:
        if conn:
            conn.close()
    if sent:
        return JSONResponse({"status": "already_sent", "channel": sent.get("selectedChannel"),
                             "sentAt": sent.get("sentAt")}, status_code=200)

    from modules.income import _get_client_phone  # lazy: income imports a lot
    from modules.notificationDispatch import dispatch_notification_connector  # lazy: avoids a cycle
    client = _client(client_id)
    first_name = str(client.get("first_name") or "").strip()
    company = company_name({"companyId": company_id})
    text = message(first_name, company)
    phone_conn = connection()
    try:
        phone = _get_client_phone(phone_conn, client_id)
    finally:
        phone_conn.close()

    response = await dispatch_notification_connector({
        "companyId": company_id, "sourceType": SOURCE_TYPE, "sourceId": income_id,
        "recipientType": "client", "recipientId": client_id, "eventName": EVENT,
        "phone": phone, "pushTitle": config["pushTitle"], "pushMessage": text,
        "waSmsMessage": text, "messagePreview": f"Servicio listo · venta {income_id}",
        "waTemplate": config["waTemplate"], "waParams": [first_name or "cliente", company or "tu negocio"],
        "navigationRoute": config["navigationRoute"],
    })
    try:
        result = json.loads(response.body)
    except (TypeError, ValueError):
        result = {}
    # No phone, name or message text in the logs.
    log_workflow_step("service_completion_notice", workflow_name="client_notifications", entity="income",
                      entity_id=income_id, status="COMPLETED" if result.get("status") == "sent" else "FAILED",
                      message=f"userId={user_id} company={company_id} http={response.status_code} "
                              f"channel={result.get('selectedChannel')}")
    if response.status_code == 200 and isinstance(result.get("result"), dict):  # resolved meanwhile
        return JSONResponse({"status": "already_sent", "channel": result["result"].get("selectedChannel")},
                            status_code=200)
    if response.status_code == 200 and result.get("status") == "sent":
        return JSONResponse({"status": "sent", "channel": result.get("selectedChannel"),
                             "attempted": [a.get("channel") for a in result.get("attemptedChannels") or []]},
                            status_code=200)
    return JSONResponse({"error": "send_failed", "fallbackReason": result.get("fallbackReason"),
                         "detail": result.get("error")}, status_code=502)
