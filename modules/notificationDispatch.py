from fastapi.responses import JSONResponse
from databases import connection
import json
from datetime import datetime, timezone

from observability import log_workflow_step, log_audit
from observability.integrations import timed_integration
from modules.ticket_notifications import send_sms, send_whatsapp
from modules.azure_notifications import send_azure_push

# sp_notificationDispatches action codes -> a human label for workflow/audit logs.
_ACTION_LABELS = {1: "Insert", 2: "Update", 3: "Delete"}


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


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
        "SELECT channel_list_json, allow_sms_fallback FROM dbo.notificationDispatch_policy WHERE eventName = %s",
        (event_name,),
    )
    row = cursor.fetchone()
    if not row:
        return None
    channel_list_json, allow_sms_fallback = row[0], row[1]
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
    (modules/pushNotifications.py:128, modules/automatedPayments.py:408):
    dbo.clients has no userId column, so the only path is
    `SELECT TOP 1 userId FROM users WHERE clientId = %s`.

    Returns the userId to target, or None if this recipient has no linked
    user account at all (the real "no push possible" case -- NOT the same as
    "has an account but no device installed", which this system has no way
    to detect: Azure NH returns 2xx for a tag with zero matching devices, so
    a successful push call here is fire-and-hope, same as everywhere else in
    this backend -- not a stronger guarantee than existing push call sites.
    """
    if recipient_type == "user":
        return recipient_id
    cursor.execute("SELECT TOP 1 userId FROM users WHERE clientId = %s", (recipient_id,))
    row = cursor.fetchone()
    return row[0] if row else None


def _existing_resolved_dispatch(cursor, company_id, source_type, source_id, event_name):
    cursor.execute(
        """
        SELECT TOP 1 notificationDispatchId, selectedChannel, status, providerMessageId, sentAt, confirmedAt
        FROM dbo.notificationDispatches
        WHERE companyId = %s AND sourceType = %s AND sourceId = %s AND eventName = %s
          AND status IN ('sent', 'confirmed')
        """,
        (company_id, source_type, source_id, event_name),
    )
    row = cursor.fetchone()
    if not row:
        return None
    return {
        "notificationDispatchId": row[0],
        "selectedChannel": row[1],
        "status": row[2],
        "providerMessageId": row[3],
        "sentAt": row[4].isoformat() if row[4] else None,
        "confirmedAt": row[5].isoformat() if row[5] else None,
    }


async def dispatch_notification_connector(payload: dict) -> JSONResponse:
    """
    Push -> WhatsApp -> SMS cost-minimizing cascade for one notification event.

    Push eligibility for recipientType == "client": Azure Notification Hub
    tags devices as user_{userId} only -- never clientId (see
    modules/azure_notifications.py::_send_single), and dbo.clients has no
    userId column. So _resolve_push_user_id() looks up the linked app
    account via `SELECT TOP 1 userId FROM users WHERE clientId = %s` -- the
    same idiom already used at modules/pushNotifications.py:128 and
    modules/automatedPayments.py:408 -- and only skips push (fallbackReason=
    NO_DEVICE) when that client has no linked user account at all.

    IMPORTANT, honest limitation this connector cannot fix on its own: there
    is no local device/installation table anywhere in this backend. Azure NH
    returns 2xx for a tag with zero matching devices, so a "sent" push here
    is fire-and-hope -- exactly like every other push call site in this
    codebase -- not a stronger delivery guarantee. A resolved userId means
    "this recipient has an app account," not "this recipient's phone is
    definitely holding a live push token right now."

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
        if receipt_url:
            wa_sms_message = f"{wa_sms_message}\n{receipt_url}"
        push_title = payload.get("pushTitle") or event_name
        push_message = payload.get("pushMessage") or message_preview

        required = [company_id, source_type, source_id, recipient_type, recipient_id, event_name]
        if any(v is None for v in required):
            return JSONResponse(
                content={"error": "companyId, sourceType, sourceId, recipientType, recipientId and eventName are required"},
                status_code=400,
            )

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

        with log_workflow_step(
            f"NotificationDispatch cascade start ({event_name})",
            workflow_name="notification_dispatch",
            action="DISPATCH",
            status="STARTED",
            entity="notificationDispatches",
        ):
            pass

        for channel in channels:
            if channel == "push":
                push_user_id = _resolve_push_user_id(cursor, recipient_type, recipient_id)
                if push_user_id is None:
                    attempted.append({"channel": "push", "outcome": "NO_DEVICE", "at": _now_iso()})
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
                        "twilio_whatsapp", "dispatch", request={"to": phone},
                    ) as span:
                        result = send_whatsapp(phone, wa_sms_message)
                        span.response = result
                        span.http_status = 200
                    selected_channel = "whatsapp"
                    provider_name = "twilio_whatsapp"
                    provider_message_id = result.get("messageSid")
                    status = "sent"
                    attempted.append({"channel": "whatsapp", "outcome": "SENT", "at": _now_iso()})
                    break
                except Exception as e:
                    # Covers a Twilio 24h-window freeform rejection (error 63016) same as any other Twilio failure.
                    attempted.append({"channel": "whatsapp", "outcome": "WHATSAPP_UNAVAILABLE", "at": _now_iso(), "error": str(e)})
                    fallback_reason = fallback_reason or "WHATSAPP_UNAVAILABLE"
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
                continue

        if selected_channel is None:
            selected_channel = channels[-1]

        now_iso = _now_iso()
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
                "messagePreview": message_preview,
                "sentAt": now_iso if status == "sent" else None,
                "failedAt": now_iso if status == "failed" else None,
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
        cursor.execute(
            "SELECT TOP 1 notificationDispatchId, companyId FROM dbo.notificationDispatches WHERE providerMessageId = %s",
            (provider_message_id,),
        )
        row = cursor.fetchone()
        if not row:
            return JSONResponse(content={"error": "No dispatch found for that providerMessageId"}, status_code=404)

        dispatch_id, company_id = row[0], row[1]
        now_iso = _now_iso()
        update_payload = {
            "notificationDispatches": [{
                "action": 2,
                "notificationDispatchId": dispatch_id,
                "companyId": company_id,
                "status": new_status,
                "confirmedAt": now_iso if new_status == "confirmed" else None,
                "failedAt": now_iso if new_status == "failed" else None,
            }]
        }
        return notificationDispatch_sp(update_payload)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
