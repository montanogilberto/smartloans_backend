import base64
import hashlib
import hmac
import json
import os
import time
import urllib.parse

import httpx


AZURE_CONNECTION_STRING = os.getenv("AZURE_NOTIFICATION_HUB_CONNECTION_STRING", "")
AZURE_HUB_NAME = os.getenv("AZURE_NOTIFICATION_HUB_NAME", "")


def parse_connection_string(conn_str: str):
    parts = dict(item.split("=", 1) for item in conn_str.split(";") if item)
    return parts.get("Endpoint"), parts.get("SharedAccessKeyName"), parts.get("SharedAccessKey")


def generate_sas_token(uri: str, sas_key_name: str, sas_key: str) -> str:
    target_uri = urllib.parse.quote_plus(uri).lower()
    expiry = int(time.time() + 3600)
    to_sign = f"{target_uri}\n{expiry}"

    signature = base64.b64encode(
        hmac.new(sas_key.encode("utf-8"), to_sign.encode("utf-8"), hashlib.sha256).digest()
    ).decode("utf-8")

    return (
        f"SharedAccessSignature sig={urllib.parse.quote_plus(signature)}"
        f"&se={expiry}&skn={sas_key_name}"
    )


async def send_azure_push(title: str, message: str, target_user_id: int = None):
    if not AZURE_CONNECTION_STRING or not AZURE_HUB_NAME:
        return 0

    endpoint, key_name, key = parse_connection_string(AZURE_CONNECTION_STRING)
    if not endpoint or not key_name or not key:
        return 0

    base_url = endpoint.replace("sb://", "https://").rstrip("/")
    uri = f"{base_url}/{AZURE_HUB_NAME}/messages/"
    url = f"{uri}?api-version=2015-01"

    token = generate_sas_token(uri, key_name, key)

    payload = {
        "notification": {"title": title, "body": message},
        "data": {"title": title, "body": message},
    }

    headers = {
        "Authorization": token,
        "Content-Type": "application/json;charset=utf-8",
        "ServiceBusNotification-Format": "gcm",
    }

    if target_user_id:
        headers["ServiceBusNotification-Tags"] = f"user_{target_user_id}"

    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.post(url, headers=headers, content=json.dumps(payload))
        return response.status_code
