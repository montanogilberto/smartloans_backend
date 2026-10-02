import json
import logging
import os

from fastapi import APIRouter, BackgroundTasks, Request
from starlette.responses import JSONResponse, PlainTextResponse, Response

from modules.whatsappChannels import run_migration, whatsapp_channels_sp
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


@router.post(
    "/whatsapp/channels",
    summary="WhatsApp numbers (Cloud API) per company/branch",
    description="""
One WhatsApp number per branch. The webhook routes every inbound message by
Meta's phone_number_id to the channel registered here.

action 0 (or omit) — list: { "whatsappChannels": [{ "companyId": int }] }
action 1 — register / re-point a number (matched by phoneNumberId):
  { "whatsappChannels": [{ "action": 1, "companyId": int, "branchId"?: int,
    "phoneNumberId": str, "wabaId"?: str, "displayPhoneNumber"?: str,
    "accessTokenRef"?: str (App Service setting name; default WA_ACCESS_TOKEN),
    "botEnabled"?: bool }] }
action 2 — bot / channel on-off:
  { "whatsappChannels": [{ "action": 2, "companyId": int, "channelId": int,
    "botEnabled"?: bool, "isActive"?: bool }] }
→ { "result": [{ "whatsappChannels": [...] }] }
""",
)
def whatsapp_channels(json: dict):
    return whatsapp_channels_sp(json)


@router.post(
    "/whatsapp/cloud/migrate",
    summary="Create whatsappChannels / whatsappConversations tables + SPs (idempotent)",
)
def whatsapp_cloud_migrate():
    try:
        return JSONResponse(run_migration(), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
