from fastapi.responses import JSONResponse
from databases import connection
import asyncio
import json
from datetime import datetime, timezone

from observability import log_workflow_step, log_audit
from observability.integrations import timed_integration
from modules.ticket_notifications import send_sms, send_whatsapp
from modules.azure_notifications import has_push_device, send_azure_push
from modules.pushNotifications import resolve_push_user_ids

# sp_notificationDispatches action codes -> a human label for workflow/audit logs.
_ACTION_LABELS = {1: "Insert", 2: "Update", 3: "Delete"}


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _now_sql() -> str:
    """UTC timestamp SQL Server DATETIME can parse. isoformat()'s '+00:00'
    offset and 6-digit fraction made TRY_CONVERT(DATETIME, ...) return NULL,
    so sentAt/confirmedAt/failedAt were never stored."""
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3]


def _short(text, limit: int) -> str | None:
    text = (str(text) if text is not None else '').strip()
    return text[:limit] or None


# ---------------------------------------------------------------------------
# Standard CRUD (sp_notificationDispatches / _all / _one)
# ---------------------------------------------------------------------------

def notificationDispatch_sp(json_file: dict):
    conn = None
    try:
        rows_in = (json_file or {}).get("notificationDispatches") or [{}]
        first_in = rows_in[0] if rows_in else {}
        action = first_in.get("action")
        dispatch_id_in = first_in.get("notificationDispatchId")

        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_notificationDispatches @pjsonfile = %s", (json.dumps(json_file),))

        result_row = cursor.fetchall()
        if not result_row:
            return JSONResponse(content={"result": [], "msg": "No data returned"}, status_code=204)

        result = [{"value": row[0], "msg": row[1], "error": row[2]} for row in result_row]
        first_out = result[0] if result else {}
        failed = str(first_out.get("error") or "") == "1"
        entity_id_raw = dispatch_id_in or first_out.get("value")
        entity_id = int(entity_id_raw) if str(entity_id_raw or "").isdigit() else None
        action_label = _ACTION_LABELS.get(action, "Mutation")

        log_workflow_step(
            f"NotificationDispatch {action_label}",
            workflow_name="notification_dispatch",
            action=action_label.upper(),
            status="FAILED" if failed else "SUCCESS",
            entity="notificationDispatches",
            entity_id=entity_id,
            message=first_out.get("msg") or first_in.get("eventName"),
        )

        if not failed and action in (1, 2) and entity_id is not None:
            log_audit(
                "notificationDispatches", entity_id, "status", None, first_in.get("status"),
                action="INSERT" if action == 1 else "UPDATE",
            )

        return JSONResponse(content={"result": result}, status_code=200)
    except Exception as e:
        log_workflow_step(
            "NotificationDispatch Mutation Error", workflow_name="notification_dispatch",
            status="FAILED", entity="notificationDispatches", message=str(e),
        )
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_notificationDispatch_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_notificationDispatches_all @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows)
        result = json.loads(json_result) if json_result else {"notificationDispatches": []}
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def one_notificationDispatch_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_notificationDispatches_one @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows)
        result = json.loads(json_result) if json_result else {"notificationDispatches": []}
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


# ---------------------------------------------------------------------------
# Connector: POST /notificationDispatch/dispatch
# ---------------------------------------------------------------------------

def _get_policy(cursor, event_name: str):
    cursor.execute(
        "EXEC sp_notificationDispatchPolicy_one @pjsonfile = %s",
        (json.dumps({"notificationDispatchPolicies": [{"eventName": event_name}]}),),
    )
    # FOR JSON AUTO may split the payload across several rows
    rows = cursor.fetchall()
    json_text = "".join((r[0] or "") for r in rows).strip() if rows else ""
    if not json_text:
        return None
    policies = json.loads(json_text).get("notificationDispatchPolicies") or []
    if not policies:
        return None
    channel_list_json = policies[0].get("channel_list_json")
    allow_sms_fallback = policies[0].get("allow_sms_fallback")
    try:
        channels = json.loads(channel_list_json)
    except (TypeError, ValueError):
        channels = []
    return {"channels": channels, "allow_sms_fallback": bool(allow_sms_fallback)}


def _resolve_push_user_id(cursor, recipient_type: str, recipient_id):
    """
    Azure Notification Hub tags devices as user_{userId} -- never clientId
    (see modules/azure_notifications.py). If recipientType is already "user",
    recipientId IS the userId. If recipientType is "client", resolve the
    linked app account the same way the rest of this backend already does
    (modules/pushNotifications.py, modules/automatedPayments.py):
    dbo.clients has no userId column, so the only path is dbo.users.clientId,
    read via sp_pushNotifications_resolveUsers.

    Returns the userId to target, or None if this recipient has no linked
    user account at all. Whether that account has a device registered is a
    separate check (has_push_device), done by the cascade before sending.
    """
    if recipient_type == "user":
        return recipient_id
    try:
        client_id = int(recipient_id)
    except (TypeError, ValueError):
        return None
    return resolve_push_user_ids(cursor, [client_id]).get(client_id)


def _lookup(cursor, item: dict) -> list:
    """sp_notificationDispatches_lookup -> list of matching rows ([] if none)."""
    cursor.execute(
        "EXEC sp_notificationDispatches_lookup @pjsonfile = %s",
        (json.dumps({"notificationDispatches": [item]}),),
    )
    # FOR JSON may split the payload across several rows
    rows = cursor.fetchall()
    json_text = "".join((r[0] or "") for r in rows).strip() if rows else ""
    if not json_text:
        return []
    parsed = json.loads(json_text)
    if isinstance(parsed, dict) and "error" in parsed:
        raise RuntimeError(f"sp_notificationDispatches_lookup: {parsed['error']}")
    return parsed.get("notificationDispatches") or [] if isinstance(parsed, dict) else []


def _existing_resolved_dispatch(cursor, company_id, source_type, source_id, event_name):
    rows = _lookup(cursor, {
        "action": "resolved",
        "companyId": company_id,
        "sourceType": source_type,
        "sourceId": source_id,
        "eventName": event_name,
    })
    if not rows:
        return None
    row = rows[0]
    return {
        "notificationDispatchId": row.get("notificationDispatchId"),
        "selectedChannel": row.get("selectedChannel"),
        "status": row.get("status"),
        "providerMessageId": row.get("providerMessageId"),
        "sentAt": row.get("sentAt"),
        "confirmedAt": row.get("confirmedAt"),
    }


async def dispatch_notification_connector(payload: dict) -> JSONResponse:
    """
    Push -> WhatsApp -> SMS cost-minimizing cascade for one notification event.

    Push eligibility for recipientType == "client": Azure Notification Hub
    tags devices as user_{userId} only -- never clientId (see
    modules/azure_notifications.py::_send_single), and dbo.clients has no
    userId column. So _resolve_push_user_id() looks up the linked app
    account via sp_pushNotifications_resolveUsers -- the same resolver
    modules/pushNotifications.py and modules/automatedPayments.py use --
    and skips push (fallbackReason=NO_DEVICE) when that client has no linked
    user account, or the hub has no device registered under its tag for the
    platform(s) we send to (has_push_device). A "sent" push still only means
    the hub accepted it: if the hub lacks that platform's credentials (FCM v1
    / APNs), it is dropped there without an error.

    WhatsApp accepted by Meta can still fail seconds later (131026, 131047…).
    That arrives by webhook; apply_provider_status then sends the SMS step
    (sms_after_whatsapp_failure).

    Body: {
      companyId, sourceType, sourceId, recipientType, recipientId, eventName,
      phone,               # E.164, required for whatsapp/sms fallback
      pushTitle, pushMessage,     # used only if a push attempt is made
      waSmsMessage,               # body used for whatsapp/sms
      messagePreview,             # short summary stored on the row
      receiptUrl                  # optional, appended to waSmsMessage if given
    }
    """
    conn = None
    try:
        company_id = payload.get("companyId")
        source_type = payload.get("sourceType")
        source_id = payload.get("sourceId")
        recipient_type = payload.get("recipientType")
        recipient_id = payload.get("recipientId")
        event_name = payload.get("eventName")
        phone = payload.get("phone")
        message_preview = payload.get("messagePreview") or ""
        wa_sms_message = payload.get("waSmsMessage") or message_preview
        receipt_url = payload.get("receiptUrl")
        # Meta template (docs/whatsapp-templates.md) — built before the URL
        # is appended to the free-form text, which the template carries apart.
        if receipt_url:
            wa_template, wa_params = "comprobante_listo", [wa_sms_message, receipt_url]
        else:
            wa_template, wa_params = "detalle_compra", [wa_sms_message]
        if receipt_url:
            wa_sms_message = f"{wa_sms_message}\nVer su ticket: {receipt_url}"
        push_title = payload.get("pushTitle") or event_name
        push_message = payload.get("pushMessage") or message_preview

        required = [company_id, source_type, source_id, recipient_type, recipient_id, event_name]
        if any(v is None for v in required):
            return JSONResponse(
                content={"error": "companyId, sourceType, sourceId, recipientType, recipientId and eventName are required"},
                status_code=400,
            )

        # Walk-in ("mostrador") sales carry clientId 1, a placeholder, not a
        # person: notifying it pushed every anonymous receipt to whichever
        # staff account is linked to client 1 (43 of 166 dispatches, Sep–Oct 2026).
        if is_walk_in(recipient_type, recipient_id):
            return JSONResponse(content={"skipped": True, "reason": "walk_in_client"}, status_code=200)

        conn = connection()
        cursor = conn.cursor()

        # Idempotency: never re-send if this (companyId, sourceType, sourceId,
        # eventName) already resolved. sp_notificationDispatches also enforces
        # this on INSERT, but checking here avoids burning a Twilio/Azure call
        # first and then discovering the insert would have been rejected.
        existing = _existing_resolved_dispatch(cursor, company_id, source_type, source_id, event_name)
        if existing:
            return JSONResponse(content={"result": existing, "note": "already resolved, not re-sent"}, status_code=200)

        policy = _get_policy(cursor, event_name)
        if not policy or not policy["channels"]:
            return JSONResponse(
                content={"error": f"No notificationDispatch_policy row for eventName '{event_name}'"},
                status_code=400,
            )

        channels = policy["channels"]
        allow_sms_fallback = policy["allow_sms_fallback"]
        preferred_channel = channels[0]
        attempted = []
        selected_channel = None
        provider_message_id = None
        provider_name = None
        fallback_reason = None
        status = "failed"
        # Last provider error, saved on the row when the cascade ends failed.
        last_error_code = None
        last_error_message = None

        log_workflow_step(
            f"NotificationDispatch cascade start ({event_name})",
            workflow_name="notification_dispatch",
            action="DISPATCH",
            status="STARTED",
            entity="notificationDispatches",
        )

        for channel in channels:
            if channel == "push":
                push_user_id = _resolve_push_user_id(cursor, recipient_type, recipient_id)
                if push_user_id is None:
                    attempted.append({"channel": "push", "outcome": "NO_DEVICE", "at": _now_iso()})
                    fallback_reason = fallback_reason or "NO_DEVICE"
                    continue
                # The hub answers 2xx for a tag with no devices, so without this
                # check a client with an app account but no phone registered got
                # a "sent" push, the cascade stopped, and nothing reached them.
                device = await has_push_device(push_user_id)
                if not device["registered"]:
                    attempted.append({"channel": "push", "outcome": "NO_DEVICE", "at": _now_iso(),
                                      "detail": device["reason"], "platforms": device["platforms"]})
                    fallback_reason = fallback_reason or "NO_DEVICE"
                    continue
                try:
                    with timed_integration(
                        "azure_notification_hub", "dispatch",
                        request={"targetUserId": push_user_id, "title": push_title},
                    ) as span:
                        result = await send_azure_push(
                            title=push_title, message=push_message, target_user_id=push_user_id,
                            data={"navigationRoute": None, "sourceType": source_type, "sourceId": source_id},
                        )
                        span.response = result
                        span.http_status = 200 if result.get("sent") else 502
                    if result.get("sent"):
                        selected_channel = "push"
                        provider_name = "azure_notification_hub"
                        status = "sent"
                        attempted.append({"channel": "push", "outcome": "SENT", "at": _now_iso()})
                        break
                    outcome = "PUSH_TIMEOUT" if result.get("reason") == "timeout" else "PUSH_REJECTED"
                    attempted.append({"channel": "push", "outcome": outcome, "at": _now_iso()})
                    fallback_reason = fallback_reason or outcome
                except Exception as e:
                    attempted.append({"channel": "push", "outcome": "PUSH_TIMEOUT", "at": _now_iso(), "error": str(e)})
                    fallback_reason = fallback_reason or "PUSH_TIMEOUT"
                # Per PRD business rule: a push-stage failure (any of the three
                # outcomes above) advances to whatsapp next -- never straight to sms.
                continue

            if channel == "whatsapp":
                if not phone:
                    attempted.append({"channel": "whatsapp", "outcome": "WHATSAPP_UNAVAILABLE", "at": _now_iso(), "error": "no phone"})
                    fallback_reason = fallback_reason or "WHATSAPP_UNAVAILABLE"
                    continue
                try:
                    with timed_integration(
                        "whatsapp", "dispatch", request={"to": phone, "template": wa_template},
                    ) as span:
                        result = send_whatsapp(phone, wa_sms_message, wa_template, wa_params)
                        span.response = result
                        span.http_status = 200
                    selected_channel = "whatsapp"
                    provider_name = f"{result.get('provider', 'meta')}_whatsapp"
                    provider_message_id = result.get("messageId") or result.get("messageSid")
                    status = "sent"
                    sent_entry = {"channel": "whatsapp", "outcome": "SENT", "at": _now_iso()}
                    # WhatsApp is meant to go through Meta; when it went through
                    # Twilio instead, keep why (not configured / Meta rejected).
                    if result.get("metaFallbackReason"):
                        sent_entry["metaFallbackReason"] = result["metaFallbackReason"]
                    attempted.append(sent_entry)
                    break
                except Exception as e:
                    # Meta failed or isn't set up for this message (no template, not
                    # approved, WA_SENDER_PHONE_NUMBER_ID unset) — Twilio is disabled.
                    attempted.append({"channel": "whatsapp", "outcome": "WHATSAPP_UNAVAILABLE", "at": _now_iso(), "error": str(e)})
                    fallback_reason = fallback_reason or "WHATSAPP_UNAVAILABLE"
                    last_error_code = _short(getattr(e, "code", None), 20)
                    last_error_message = _short(e, 300)
                continue

            if channel == "sms":
                if not allow_sms_fallback:
                    attempted.append({"channel": "sms", "outcome": "SKIPPED_POLICY", "at": _now_iso()})
                    continue
                if not phone:
                    attempted.append({"channel": "sms", "outcome": "FAILED", "at": _now_iso(), "error": "no phone"})
                    continue
                try:
                    with timed_integration(
                        "twilio_sms", "dispatch", request={"to": phone},
                    ) as span:
                        result = send_sms(phone, wa_sms_message)
                        span.response = result
                        span.http_status = 200
                    selected_channel = "sms"
                    provider_name = "twilio_sms"
                    provider_message_id = result.get("messageSid")
                    status = "sent"
                    attempted.append({"channel": "sms", "outcome": "SENT", "at": _now_iso()})
                    break
                except Exception as e:
                    attempted.append({"channel": "sms", "outcome": "FAILED", "at": _now_iso(), "error": str(e)})
                    last_error_code = _short(getattr(e, "code", None), 20)
                    last_error_message = _short(e, 300)
                continue

        if selected_channel is None:
            selected_channel = channels[-1]

        now_sql = _now_sql()
        insert_payload = {
            "notificationDispatches": [{
                "action": 1,
                "companyId": company_id,
                "sourceType": source_type,
                "sourceId": source_id,
                "recipientType": recipient_type,
                "recipientId": recipient_id,
                "eventName": event_name,
                "preferredChannel": preferred_channel,
                "selectedChannel": selected_channel,
                "attemptedChannels": json.dumps(attempted),
                "fallbackReason": fallback_reason,
                "status": status,
                "providerMessageId": provider_message_id,
                "providerName": provider_name,
                # Column is NVARCHAR(200); the customer still gets the full text.
                "messagePreview": message_preview[:200],
                "sentAt": now_sql if status == "sent" else None,
                "failedAt": now_sql if status == "failed" else None,
                "providerErrorCode": last_error_code if status == "failed" else None,
                "providerErrorMessage": last_error_message if status == "failed" else None,
            }]
        }

        insert_response = notificationDispatch_sp(insert_payload)
        log_workflow_step(
            f"NotificationDispatch cascade resolved ({event_name})",
            workflow_name="notification_dispatch",
            action="DISPATCH",
            status="SUCCESS" if status == "sent" else "FAILED",
            entity="notificationDispatches",
            message=f"selectedChannel={selected_channel} fallbackReason={fallback_reason}",
        )

        return JSONResponse(
            content={
                "selectedChannel": selected_channel,
                "preferredChannel": preferred_channel,
                "status": status,
                "fallbackReason": fallback_reason,
                "attemptedChannels": attempted,
                "providerMessageId": provider_message_id,
            },
            status_code=200 if status == "sent" else 502,
        )
    except Exception as e:
        log_workflow_step(
            "NotificationDispatch cascade error", workflow_name="notification_dispatch",
            status="FAILED", entity="notificationDispatches", message=str(e),
        )
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


# ---------------------------------------------------------------------------
# Connector: POST /notificationDispatch/confirm
# ---------------------------------------------------------------------------

WALK_IN_CLIENT_ID = 1

# Twilio MessageStatus -> dispatch status. Only terminal states move the row;
# queued/sending/sent/accepted are in-flight and ignored.
_TWILIO_TERMINAL = {
    "delivered": "confirmed",
    "read": "confirmed",
    "failed": "failed",
    "undelivered": "failed",
}


def is_walk_in(recipient_type, recipient_id) -> bool:
    try:
        return recipient_type == "client" and int(recipient_id) == WALK_IN_CLIENT_ID
    except (TypeError, ValueError):
        return False


def dispatch_status_for(provider_status: str) -> str | None:
    return _TWILIO_TERMINAL.get((provider_status or "").strip().lower())


async def apply_provider_status(provider_message_id: str, provider_status: str,
                                retry_delay_s: float = 2.0,
                                error_code: str | None = None,
                                error_message: str | None = None) -> dict:
    """Moves the dispatch sent with this provider message id to confirmed /
    failed from a provider delivery callback. Never raises.

    Twilio can report a rejection (~1s) before the dispatch row exists — the
    row is written right after the send call returns — so a miss is retried
    once after `retry_delay_s`."""
    new_status = dispatch_status_for(provider_status)
    if not provider_message_id or not new_status:
        return {"updated": False, "reason": "not_terminal"}
    for attempt in range(2):
        conn = None
        try:
            conn = connection()
            matches = _lookup(conn.cursor(), {"action": "byProviderMessageId",
                                              "providerMessageId": provider_message_id})
        except Exception as e:
            return {"updated": False, "reason": f"lookup_failed: {e}"}
        finally:
            if conn:
                conn.close()
        if matches:
            break
        if attempt == 0 and retry_delay_s:
            await asyncio.sleep(retry_delay_s)
    else:
        return {"updated": False, "reason": "no_dispatch"}

    dispatch_id, company_id = matches[0]["notificationDispatchId"], matches[0]["companyId"]
    now_sql = _now_sql()
    failed = new_status == "failed"
    response = notificationDispatch_sp({"notificationDispatches": [{
        "action": 2,
        "notificationDispatchId": dispatch_id,
        "companyId": company_id,
        "status": new_status,
        "confirmedAt": now_sql if new_status == "confirmed" else None,
        "failedAt": now_sql if failed else None,
        # Why it failed (Twilio ErrorCode / Meta errors[0].code) — shown in the dispatch log.
        "providerErrorCode": _short(error_code, 20) if failed else None,
        "providerErrorMessage": _short(error_message, 300) if failed else None,
    }]})
    ok = getattr(response, "status_code", 500) == 200
    result = {"updated": ok, "notificationDispatchId": dispatch_id, "status": new_status}
    if ok and failed:
        result["smsFallback"] = await sms_after_whatsapp_failure(dispatch_id, error_code)
    return result


def _dispatch_row(dispatch_id) -> dict | None:
    response = one_notificationDispatch_sp({"notificationDispatches": [{"notificationDispatchId": dispatch_id}]})
    if getattr(response, "status_code", 500) != 200:
        return None
    rows = json.loads(response.body).get("notificationDispatches") or []
    return rows[0] if rows else None


def _client_phone(client_id) -> str | None:
    # Lazy: modules.income imports this module.
    from modules.income import _get_client_phone
    return _get_client_phone(connection(), client_id)


async def sms_after_whatsapp_failure(dispatch_id, error_code=None) -> dict:
    """The cascade's SMS step for a WhatsApp that Meta accepted and then
    failed (131026 undeliverable, 131047 outside 24h…). The cascade had
    already stopped at "whatsapp SENT", so without this the customer got
    nothing. Sent as a new dispatch row (selectedChannel sms, fallbackReason
    WHATSAPP_FAILED) so the log shows both. Never raises.

    Text: the row's messagePreview (the full customer text; the column holds
    200 chars) + the signed ticket link for sales, as the cascade sends it."""
    try:
        row = _dispatch_row(dispatch_id)
        if not row or row.get("selectedChannel") != "whatsapp":
            return {"sent": False, "reason": "not_whatsapp"}
        if row.get("recipientType") != "client" or is_walk_in("client", row.get("recipientId")):
            return {"sent": False, "reason": "no_client_phone"}

        conn = connection()
        try:
            cursor = conn.cursor()
            policy = _get_policy(cursor, row["eventName"])
            # Duplicate webhooks: once the SMS row is 'sent' this finds it.
            existing = _existing_resolved_dispatch(cursor, row["companyId"], row["sourceType"],
                                                   row["sourceId"], row["eventName"])
        finally:
            conn.close()
        if existing:
            return {"sent": False, "reason": "already_resolved"}
        if not policy or not policy["allow_sms_fallback"] or "sms" not in policy["channels"]:
            return {"sent": False, "reason": "policy_no_sms"}

        phone = _client_phone(row["recipientId"])
        if not phone:
            return {"sent": False, "reason": "no_client_phone"}
        body = row.get("messagePreview") or ""
        if row.get("sourceType") == "income":
            from modules.receiptLinks import receipt_link
            link = receipt_link(row["companyId"], row["sourceId"])
            if link:
                body = f"{body}\nVer su ticket: {link}"

        attempted = [{"channel": "whatsapp", "outcome": "FAILED_AFTER_SEND", "at": _now_iso(),
                      "providerErrorCode": _short(error_code, 20),
                      "notificationDispatchId": dispatch_id}]
        status, provider_message_id, error = "failed", None, None
        try:
            with timed_integration("twilio_sms", "dispatch_after_whatsapp", request={"to": phone}) as span:
                sms = send_sms(phone, body)
                span.response = sms
                span.http_status = 200
            status, provider_message_id = "sent", sms.get("messageSid")
            attempted.append({"channel": "sms", "outcome": "SENT", "at": _now_iso()})
        except Exception as e:
            error = e
            attempted.append({"channel": "sms", "outcome": "FAILED", "at": _now_iso(), "error": str(e)})

        now_sql = _now_sql()
        notificationDispatch_sp({"notificationDispatches": [{
            "action": 1,
            "companyId": row["companyId"],
            "sourceType": row["sourceType"],
            "sourceId": row["sourceId"],
            "recipientType": row["recipientType"],
            "recipientId": row["recipientId"],
            "eventName": row["eventName"],
            "preferredChannel": row.get("preferredChannel"),
            "selectedChannel": "sms",
            "attemptedChannels": json.dumps(attempted),
            "fallbackReason": "WHATSAPP_FAILED",
            "status": status,
            "providerMessageId": provider_message_id,
            "providerName": "twilio_sms",
            "messagePreview": (row.get("messagePreview") or "")[:200],
            "sentAt": now_sql if status == "sent" else None,
            "failedAt": now_sql if status == "failed" else None,
            "providerErrorCode": _short(getattr(error, "code", None), 20) if error else None,
            "providerErrorMessage": _short(error, 300) if error else None,
        }]})
        log_workflow_step(
            "NotificationDispatch SMS after WhatsApp failure",
            workflow_name="notification_dispatch", action="DISPATCH",
            status="SUCCESS" if status == "sent" else "FAILED", entity="notificationDispatches",
            message=f"whatsappDispatchId={dispatch_id} errorCode={error_code}",
        )
        return {"sent": status == "sent", "reason": "ok" if status == "sent" else "sms_failed"}
    except Exception as e:
        return {"sent": False, "reason": f"error: {e}"}


async def confirm_notification_connector(payload: dict) -> JSONResponse:
    """
    Manual/test confirmation hook: { providerMessageId, status: "confirmed"|"failed" }.

    NOTE: this does NOT yet parse a real Twilio status-callback POST (those
    arrive as application/x-www-form-urlencoded with MessageSid/MessageStatus,
    same shape routes_/whatsapp.py's /whatsapp/status already handles). Wiring
    TWILIO_WHATSAPP_STATUS_CALLBACK_URL / TWILIO_SMS_STATUS_CALLBACK_URL to
    this endpoint specifically is a follow-up -- left as JSON-only for now so
    it's usable for manual confirmation and testing today.
    """
    conn = None
    try:
        provider_message_id = payload.get("providerMessageId")
        new_status = payload.get("status")
        if not provider_message_id or new_status not in ("confirmed", "failed"):
            return JSONResponse(
                content={"error": "providerMessageId and status ('confirmed' or 'failed') are required"},
                status_code=400,
            )

        conn = connection()
        cursor = conn.cursor()
        matches = _lookup(cursor, {"action": "byProviderMessageId", "providerMessageId": provider_message_id})
        if not matches:
            return JSONResponse(content={"error": "No dispatch found for that providerMessageId"}, status_code=404)

        dispatch_id, company_id = matches[0]["notificationDispatchId"], matches[0]["companyId"]
        now_sql = _now_sql()
        update_payload = {
            "notificationDispatches": [{
                "action": 2,
                "notificationDispatchId": dispatch_id,
                "companyId": company_id,
                "status": new_status,
                "confirmedAt": now_sql if new_status == "confirmed" else None,
                "failedAt": now_sql if new_status == "failed" else None,
            }]
        }
        return notificationDispatch_sp(update_payload)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
