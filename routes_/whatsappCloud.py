import json
import logging
import os

from fastapi import APIRouter, BackgroundTasks, Request
from starlette.responses import PlainTextResponse, Response

from modules.whatsappCloud import handle_webhook, verify_signature

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get(
    "/whatsapp/cloud/webhook",
    summary="WhatsApp Cloud API webhook verification",
    description="Meta calls this once when the Callback URL is saved: echoes hub.challenge if hub.verify_token matches WA_VERIFY_TOKEN.",
)
async def whatsapp_cloud_verify(request: Request):
    params = request.query_params
    expected = os.getenv("WA_VERIFY_TOKEN", "")
    if (params.get("hub.mode") == "subscribe" and expected
            and params.get("hub.verify_token") == expected):
        return PlainTextResponse(params.get("hub.challenge", ""))
    logger.warning("[whatsappCloud] webhook verification failed")
    return PlainTextResponse("Forbidden", status_code=403)


@router.post(
    "/whatsapp/cloud/webhook",
    summary="WhatsApp Cloud API webhook (Meta)",
    description="Inbound messages and status updates from Meta. Signed with X-Hub-Signature-256.",
)
async def whatsapp_cloud_webhook(request: Request, background_tasks: BackgroundTasks):
    raw = await request.body()
    if not verify_signature(raw, request.headers.get("x-hub-signature-256")):
        return Response(status_code=401)
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return Response(status_code=400)
    # Answer Meta immediately; slow work (DB, LLM, replies) must not delay the
    # 200 or Meta retries and eventually disables the webhook.
    background_tasks.add_task(handle_webhook, payload)
    return Response(status_code=200)
