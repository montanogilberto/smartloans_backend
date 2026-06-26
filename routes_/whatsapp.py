

import json
import logging
from fastapi import APIRouter, Request
from starlette.responses import Response, JSONResponse
from twilio.twiml.messaging_response import MessagingResponse

from modules.whatsapp import log_message_to_database

router = APIRouter()
logger = logging.getLogger(__name__)


def _empty_twiml_response() -> Response:
    """
    Return empty TwiML with HTTP 200 so Twilio treats webhook as healthy.
    """
    twiml = "<Response></Response>"
    return Response(content=twiml, media_type="application/xml", status_code=200)


@router.post("/whatsapp", summary="WhatsApp Webhook", description="Endpoint to handle incoming WhatsApp messages")
async def whatsapp_webhook(request: Request):
    """
    Twilio WhatsApp inbound webhook.
    Supports Twilio form-encoded payloads and JSON fallback.
    Always returns HTTP 200 with valid TwiML to avoid Twilio 11200 retries/failures.
    """
    try:
        content_type = (request.headers.get("content-type") or "").lower()
        logger.info("[whatsapp_webhook] hit | content_type=%s", content_type)

        # Preferred path for Twilio webhooks
        if "application/x-www-form-urlencoded" in content_type or "multipart/form-data" in content_type:
            form = await request.form()
            phone_number = (form.get("From") or "").replace("whatsapp:", "")
            message_body = form.get("Body") or ""
            message_sid = form.get("MessageSid") or ""
            message_status = form.get("SmsStatus") or form.get("MessageStatus") or "received"

            logger.info(
                "[whatsapp_webhook] parsed form | message_sid=%s from=%s status=%s",
                message_sid, phone_number, message_status
            )

            log_message_to_database(
                phone_number=phone_number,
                message_body=message_body,
                response_body="",
                direction="inbound",
                status=message_status,
                action=1
            )

            logger.info("[whatsapp_webhook] db log done | message_sid=%s", message_sid)

            # No auto-reply required, just acknowledge Twilio.
            return _empty_twiml_response()

        # JSON fallback for internal/manual integrations
        data = await request.json()
        messages = data.get("messages", [])
        logger.info("[whatsapp_webhook] parsed json | messages_count=%s", len(messages))

        for message in messages:
            phone_number = message.get("phoneNumber", "")
            message_body = message.get("messageBody", "")
            response_body = message.get("responseBody", "")
            direction = message.get("direction", "inbound")
            status = message.get("status", "received")
            action = message.get("action", 1)

            logger.info(
                "[whatsapp_webhook] json message | phone=%s direction=%s status=%s",
                phone_number, direction, status
            )
            log_message_to_database(
                phone_number=phone_number,
                message_body=message_body,
                response_body=response_body,
                direction=direction,
                status=status,
                action=action
            )

        # Return valid TwiML for Twilio compatibility
        response = MessagingResponse()
        logger.info("[whatsapp_webhook] success | response=200")
        return Response(content=str(response), media_type="application/xml", status_code=200)

    except json.JSONDecodeError:
        logger.warning("[whatsapp_webhook] JSON decode error; returning safe TwiML 200")
        # If body is not JSON and not form-parsable, still acknowledge Twilio
        return _empty_twiml_response()
    except Exception as e:
        logger.exception("[whatsapp_webhook] unexpected error: %s", str(e))
        # Never return 5xx to Twilio callback endpoints
        return JSONResponse(content={"ok": True, "warning": str(e)}, status_code=200)


@router.post("/whatsapp/status", summary="WhatsApp Status Callback", description="Twilio status callback endpoint for WhatsApp delivery events")
async def whatsapp_status_callback(request: Request):
    """
    Receives Twilio outbound status updates (queued/sent/delivered/failed/undelivered).
    Must respond quickly with HTTP 200.
    """
    try:
        content_type = (request.headers.get("content-type") or "").lower()
        logger.info("[whatsapp_status_callback] hit | content_type=%s", content_type)

        if "application/x-www-form-urlencoded" in content_type or "multipart/form-data" in content_type:
            form = await request.form()
            from_phone = (form.get("From") or "").replace("whatsapp:", "")
            to_phone = (form.get("To") or "").replace("whatsapp:", "")
            message_status = form.get("MessageStatus") or form.get("SmsStatus") or ""
            message_body = form.get("Body") or ""
            message_sid = form.get("MessageSid") or ""

            logger.info(
                "[whatsapp_status_callback] parsed form | message_sid=%s from=%s to=%s status=%s",
                message_sid, from_phone, to_phone, message_status
            )

            log_message_to_database(
                phone_number=to_phone or from_phone,
                message_body=message_body,
                response_body="",
                direction="outbound",
                status=message_status,
                action=1
            )

            logger.info("[whatsapp_status_callback] db log done | message_sid=%s", message_sid)
            return JSONResponse(content={"ok": True}, status_code=200)

        # JSON fallback
        payload = await request.json()
        logger.info(
            "[whatsapp_status_callback] parsed json | message_sid=%s status=%s",
            payload.get("MessageSid", ""),
            payload.get("MessageStatus", "")
        )
        log_message_to_database(
            phone_number=payload.get("To", "") or payload.get("From", ""),
            message_body=payload.get("Body", ""),
            response_body="",
            direction="outbound",
            status=payload.get("MessageStatus", ""),
            action=1
        )
        logger.info("[whatsapp_status_callback] success | response=200")
        return JSONResponse(content={"ok": True}, status_code=200)

    except Exception as e:
        logger.exception("[whatsapp_status_callback] unexpected error: %s", str(e))
        # Always acknowledge callback
        return JSONResponse(content={"ok": True}, status_code=200)
