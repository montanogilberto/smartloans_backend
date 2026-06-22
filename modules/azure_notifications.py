import base64
import hashlib
import hmac
import json
import logging
import os
import time
import urllib.parse
import socket

import httpx

logger = logging.getLogger("azure_notifications")

# Set AZURE_NOTIFICATION_DEBUG=true to enable verbose logging (never in production).
_DEBUG = os.getenv("AZURE_NOTIFICATION_DEBUG", "false").strip().lower() == "true"


def _dbg(msg, *args):
    if _DEBUG:
        logger.debug(msg, *args)


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


def _build_payload_and_format(fmt: str, title: str, message: str, target_user_id) -> tuple[dict, str]:
    """Return (payload, nh_format_header) for a given send format."""
    if fmt == "fcmv1":
        return (
            {"message": {
                "notification": {"title": title, "body": message},
                "android": {"notification": {"channel_id": "push_notifications", "sound": "default"}},
            }},
            "fcmv1",
        )
    if fmt == "apns":
        return (
            {"aps": {"alert": {"title": title, "body": message}}},
            "apple",
        )
    # gcm legacy fallback
    return (
        {"data": {"title": title, "body": message,
                  "targetUserId": str(target_user_id) if target_user_id else ""}},
        "gcm",
    )


async def _send_single(url: str, sas_token: str, fmt: str, payload: dict,
                       target_user_id) -> dict:
    nh_format = fmt  # already the NH header value
    headers = {
        "Authorization": sas_token,
        "Content-Type": "application/json;charset=utf-8",
        "ServiceBusNotification-Format": nh_format,
    }
    if target_user_id:
        headers["ServiceBusNotification-Tags"] = f"user_{target_user_id}"

    _dbg("[azure_notifications] Sending %s push. tag=user_%s", nh_format, target_user_id)

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, headers=headers, content=json.dumps(payload))
            is_sent = 200 <= response.status_code < 300
            logger.info("[azure_notifications] %s → %s", nh_format, response.status_code)
            return {
                "format": nh_format,
                "sent": is_sent,
                "reason": "ok" if is_sent else "azure_non_success_status",
                "status_code": response.status_code,
            }
    except Exception as e:
        logger.error("[azure_notifications] Exception sending %s push: %s", nh_format, e)
        return {"format": nh_format, "sent": False, "reason": "request_exception",
                "status_code": 500, "error": str(e)}


async def register_device_token(user_id, token: str, platform: str):
    logger.info("[azure_notifications] register_device_token. user_id=%s platform=%s", user_id, platform)

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
    uri = f"{base_url}/{hub_name}/installations/{installation_id}"
    url = f"{uri}?api-version=2020-06"

    sas_token = generate_sas_token(uri, key_name, key)

    tags = [f"user_{user_id}"]
    payload = {
        "installationId": installation_id,
        "platform": nh_platform,
        "pushChannel": token,
        "tags": tags,
    }

    logger.info("[azure_notifications] Registering installation. id=%s platform=%s tags=%s",
                installation_id, nh_platform, tags)

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.put(
                url,
                headers={
                    "Authorization": sas_token,
                    "Content-Type": "application/json; charset=utf-8",
                },
                content=json.dumps(payload),
            )
            success = 200 <= response.status_code < 300
            logger.info("[azure_notifications] Installation %s → %s",
                        installation_id, response.status_code)
            return {
                "success": success,
                "reason": "ok" if success else "azure_non_success_status",
                "status_code": response.status_code,
                "response_text": response.text[:500] if response.text else "",
                "installationId": installation_id,
            }
    except Exception as error:
        logger.error("[azure_notifications] Exception registering device: %s", error)
        return {
            "success": False,
            "reason": "request_exception",
            "status_code": 500,
            "error": str(error),
        }


async def send_azure_push(title: str, message: str, target_user_id: int = None):
    logger.info("[azure_notifications] send_azure_push. title=%r user_id=%s", title, target_user_id)

    connection_string = os.getenv("AZURE_NOTIFICATION_HUB_CONNECTION_STRING", "")
    hub_name = os.getenv("AZURE_NOTIFICATION_HUB_NAME", "")

    # AZURE_NOTIFICATION_HUB_FORMAT controls which platforms to send to:
    #   fcmv1  → Android only (default)
    #   apns   → iOS only
    #   all    → both Android (fcmv1) and iOS (apns)
    #   gcm    → legacy GCM fallback
    notification_format = os.getenv("AZURE_NOTIFICATION_HUB_FORMAT", "fcmv1").strip().lower() or "fcmv1"

    logger.info("[azure_notifications] Hub=%s format=%s", hub_name, notification_format)

    if not connection_string or not hub_name:
        logger.warning("[azure_notifications] Missing hub config. Skipping push.")
        return {"sent": False, "reason": "missing_config", "status_code": None}

    endpoint, key_name, key = parse_connection_string(connection_string)
    if not endpoint or not key_name or not key:
        logger.warning("[azure_notifications] Invalid connection string. Skipping push.")
        return {"sent": False, "reason": "invalid_connection_string", "status_code": None}

    endpoint = (endpoint or "").strip().strip('"').strip("'")
    hub_name = (hub_name or "").strip().strip('"').strip("'")
    base_url = endpoint.replace("sb://", "https://").rstrip("/")
    uri = f"{base_url}/{hub_name}/messages/"
    url = f"{uri}?api-version=2015-01"

    sas_token = generate_sas_token(uri, key_name, key)

    # Determine which formats to send
    if notification_format == "all":
        formats = ["fcmv1", "apns"]
    else:
        formats = [notification_format]

    results = []
    for fmt in formats:
        payload, nh_header = _build_payload_and_format(fmt, title, message, target_user_id)
        result = await _send_single(url, sas_token, nh_header, payload, target_user_id)
        results.append(result)

    any_sent = any(r["sent"] for r in results)
    return {
        "sent": any_sent,
        "reason": "ok" if any_sent else "all_failed",
        "results": results,
    }
