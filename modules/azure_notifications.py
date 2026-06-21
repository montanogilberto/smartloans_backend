import base64
import hashlib
import hmac
import json
import os
import time
import urllib.parse
import socket

import httpx


def parse_connection_string(conn_str: str):
    parts = dict(item.split("=", 1) for item in conn_str.split(";") if item)
    return parts.get("Endpoint"), parts.get("SharedAccessKeyName"), parts.get("SharedAccessKey")


def generate_sas_token(uri: str, sas_key_name: str, sas_key: str) -> str:
    encoded_uri = urllib.parse.quote_plus(uri.lower())
    expiry = str(int(time.time() + 3600))

    string_to_sign = encoded_uri + "\n" + expiry

    signature = urllib.parse.quote_plus(
        base64.b64encode(
            hmac.new(
                sas_key.encode("utf-8"),
                string_to_sign.encode("utf-8"),
                hashlib.sha256,
            ).digest()
        ).decode("utf-8")
    )

    return (
        f"SharedAccessSignature "
        f"sr={encoded_uri}"
        f"&sig={signature}"
        f"&se={expiry}"
        f"&skn={sas_key_name}"
    )


def _normalize_registration_platform(platform: str) -> str:
    platform_value = (platform or "").strip().lower()
    if platform_value == "android":
        return "fcmv1"
    if platform_value == "ios":
        return "apns"
    return ""


def _build_installation_id(user_id, token: str, platform: str) -> str:
    raw = f"{platform}:{user_id}:{token}"
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    return f"u{user_id}_{digest[:32]}"


async def register_device_token(user_id, token: str, platform: str):
    print("[azure_notifications] register_device_token called.", {
        "user_id": user_id,
        "token_length": len(token) if isinstance(token, str) else None,
        "platform": platform,
    })

    if user_id is None or not str(user_id).strip():
        return {"success": False, "reason": "missing_user_id", "status_code": 400}
    if not token or not isinstance(token, str):
        return {"success": False, "reason": "missing_token", "status_code": 400}

    nh_platform = _normalize_registration_platform(platform)
    if not nh_platform:
        return {"success": False, "reason": "invalid_platform", "status_code": 400}

    connection_string = os.getenv("AZURE_NOTIFICATION_HUB_CONNECTION_STRING", "")
    hub_name = os.getenv("AZURE_NOTIFICATION_HUB_NAME", "")

    if not connection_string or not hub_name:
        return {"success": False, "reason": "missing_config", "status_code": 500}

    endpoint, key_name, key = parse_connection_string(connection_string)
    if not endpoint or not key_name or not key:
        return {"success": False, "reason": "invalid_connection_string", "status_code": 500}

    endpoint = (endpoint or "").strip().strip('"').strip("'")
    hub_name = (hub_name or "").strip().strip('"').strip("'")
    base_url = endpoint.replace("sb://", "https://").rstrip("/")

    installation_id = _build_installation_id(user_id, token, nh_platform)
    api_version = "2020-06"
    uri = f"{base_url}/{hub_name}/installations/{installation_id}"
    url = f"{uri}?api-version={api_version}"

    sas_token = generate_sas_token(uri, key_name, key)

    tags = [f"user_{user_id}"]
    payload = {
        "installationId": installation_id,
        "platform": nh_platform,
        "pushChannel": token,
        "tags": tags,
    }

    headers = {
        "Authorization": sas_token,
        "Content-Type": "application/json; charset=utf-8",
    }

    print("[azure_notifications] Registering installation.", {
        "url": url,
        "installation_id": installation_id,
        "platform": nh_platform,
        "tags": tags,
    })

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.put(url, headers=headers, content=json.dumps(payload))
            success = 200 <= response.status_code < 300
            return {
                "success": success,
                "reason": "ok" if success else "azure_non_success_status",
                "status_code": response.status_code,
                "response_text": response.text[:500] if response.text else "",
                "installationId": installation_id,
            }
    except Exception as error:
        print("[azure_notifications] Exception while registering device:", str(error))
        return {
            "success": False,
            "reason": "request_exception",
            "status_code": 500,
            "error": str(error),
        }


async def send_azure_push(title: str, message: str, target_user_id: int = None):
    print("[azure_notifications] send_azure_push called.", {
        "title": title,
        "message_length": len(message) if isinstance(message, str) else None,
        "target_user_id": target_user_id,
    })

    # Load env vars at runtime (not import time)
    connection_string = os.getenv("AZURE_NOTIFICATION_HUB_CONNECTION_STRING", "")
    hub_name = os.getenv("AZURE_NOTIFICATION_HUB_NAME", "")
    notification_format = os.getenv("AZURE_NOTIFICATION_HUB_FORMAT", "fcm").strip().lower() or "fcm"

    print("[azure_notifications] Hub Name:", hub_name)
    print("[azure_notifications] Connection String Loaded:", bool(connection_string))

    if not connection_string or not hub_name:
        print("[azure_notifications] Missing AZURE_NOTIFICATION_HUB_CONNECTION_STRING or AZURE_NOTIFICATION_HUB_NAME. Skipping push.")
        return {"sent": False, "reason": "missing_config", "status_code": None}

    endpoint, key_name, key = parse_connection_string(connection_string)
    print("[azure_notifications] Parsed connection settings.", {
        "has_endpoint": bool(endpoint),
        "has_key_name": bool(key_name),
        "has_key": bool(key),
    })
    if not endpoint or not key_name or not key:
        print("[azure_notifications] Invalid connection string parts. Skipping push.")
        return {"sent": False, "reason": "invalid_connection_string", "status_code": None}

    endpoint = (endpoint or "").strip().strip('"').strip("'")
    hub_name = (hub_name or "").strip().strip('"').strip("'")
    base_url = endpoint.replace("sb://", "https://").rstrip("/")
    uri = f"{base_url}/{hub_name}/messages/"
    url = f"{uri}?api-version=2015-01"

    # Critical diagnostics for SAS/network troubleshooting
    print("[azure_notifications] ENDPOINT RAW:", repr(endpoint))
    print("[azure_notifications] BASE URL RAW:", repr(base_url))
    print("[azure_notifications] URL RAW:", repr(url))
    print("[azure_notifications] URI SIGNED:", uri)
    print("[azure_notifications] Computed Azure URL:", url)

    parsed = urllib.parse.urlparse(url)
    host = parsed.hostname
    print("[azure_notifications] HOST:", host)
    try:
        dns_ip = socket.gethostbyname(host) if host else None
        print("[azure_notifications] DNS:", dns_ip)
    except Exception as dns_error:
        print("[azure_notifications] DNS ERROR:", str(dns_error))

    token = generate_sas_token(uri, key_name, key)
    print("[azure_notifications] SAS token generated.")
    print("[azure_notifications] KEY NAME:", key_name)
    print("[azure_notifications] URI USED FOR SAS:", uri)
    print("[azure_notifications] TOKEN PREVIEW:", token[:150] + "...")

    # Payload by format
    if notification_format == "fcm":
        payload = {
            "message": {
                "notification": {"title": title, "body": message}
            }
        }
    else:
        # default to Azure NH legacy-compatible Android payload
        notification_format = "gcm"
        payload = {
            "title": title,
            "body": message,
            "targetUserId": str(target_user_id) if target_user_id else "",
        }

    headers = {
        "Authorization": token,
        "Content-Type": "application/json;charset=utf-8",
        "ServiceBusNotification-Format": "fcmv1",
    }

    if target_user_id:
        headers["ServiceBusNotification-Tags"] = f"user_{target_user_id}"

    print("[azure_notifications] Notification Format:", headers["ServiceBusNotification-Format"])
    print("[azure_notifications] Tag:", headers.get("ServiceBusNotification-Tags"))
    print("[azure_notifications] Payload:", json.dumps(payload))

    if not target_user_id:
        print("[azure_notifications] No target_user_id provided; sending untagged notification.")

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            print("[azure_notifications] Sending POST request to Azure Notification Hub...")
            print("[azure_notifications] HEADERS:", headers)
            print("[azure_notifications] BODY:", json.dumps(payload))
            response = await client.post(url, headers=headers, content=json.dumps(payload))
            print("[azure_notifications] Azure response received.", {
                "status_code": response.status_code,
                "response_text": response.text[:500] if response.text else "",
            })
            print("[azure_notifications] RESPONSE HEADERS:", dict(response.headers))
            print("[azure_notifications] RESPONSE BODY:", response.text[:1000] if response.text else "")
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
