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
    print("[azure_notifications] send_azure_push called.", {
        "title": title,
        "message_length": len(message) if isinstance(message, str) else None,
        "target_user_id": target_user_id,
    })

    if not AZURE_CONNECTION_STRING or not AZURE_HUB_NAME:
        print("[azure_notifications] Missing AZURE_NOTIFICATION_HUB_CONNECTION_STRING or AZURE_NOTIFICATION_HUB_NAME. Skipping push.")
        return {"sent": False, "reason": "missing_config", "status_code": None}

    endpoint, key_name, key = parse_connection_string(AZURE_CONNECTION_STRING)
    print("[azure_notifications] Parsed connection settings.", {
        "has_endpoint": bool(endpoint),
        "has_key_name": bool(key_name),
        "has_key": bool(key),
    })
    if not endpoint or not key_name or not key:
        print("[azure_notifications] Invalid connection string parts. Skipping push.")
        return {"sent": False, "reason": "invalid_connection_string", "status_code": None}

    base_url = endpoint.replace("sb://", "https://").rstrip("/")
    uri = f"{base_url}/{AZURE_HUB_NAME}/messages/"
    url = f"{uri}?api-version=2015-01"
    print("[azure_notifications] Computed Azure URL:", url)

    token = generate_sas_token(uri, key_name, key)
    print("[azure_notifications] SAS token generated.")

    payload = {
        "notification": {"title": title, "body": message},
        "data": {"title": title, "body": message},
    }
    print("[azure_notifications] Payload prepared.")

    headers = {
        "Authorization": token,
        "Content-Type": "application/json;charset=utf-8",
        "ServiceBusNotification-Format": "gcm",
    }

    if target_user_id:
        headers["ServiceBusNotification-Tags"] = f"user_{target_user_id}"
        print("[azure_notifications] Target tag applied.", {"tag": headers["ServiceBusNotification-Tags"]})
    else:
        print("[azure_notifications] No target_user_id provided; sending untagged notification.")

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            print("[azure_notifications] Sending POST request to Azure Notification Hub...")
            response = await client.post(url, headers=headers, content=json.dumps(payload))
            print("[azure_notifications] Azure response received.", {
                "status_code": response.status_code,
                "response_text": response.text[:500] if response.text else "",
            })
            is_sent = 200 <= response.status_code < 300
            return {
                "sent": is_sent,
                "reason": "ok" if is_sent else "azure_non_success_status",
                "status_code": response.status_code,
                "response_text": response.text[:500] if response.text else "",
            }
    except Exception as e:
        print("[azure_notifications] Exception while sending push:", str(e))
        raise
