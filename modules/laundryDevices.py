"""
GMO Laundry — ESP32 machine controllers.

SQL: sql/migrations/2026-10-18_laundry_devices.sql.

Flow of one machine use:
  1. The client app asks POST /laundryDevices/qrToken and shows the token as a QR.
  2. The ESP32 reads it and calls POST /laundryDevices/authorize with its own
     X-Device-Id / X-Device-Key headers and a requestId it keeps across retries.
  3. Here: check the device key, check the token signature/expiry/company, open
     the use (idempotent on deviceId + requestId), debit the machine's price as
     LAUNDRY_USAGE in walletTransactions (idempotent on the same key), settle.
  4. The ESP32 only switches the machine on when authorized = true.

The device never sends an amount — the price is laundryDevices.priceMXN.
"""

import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import time

from fastapi.responses import JSONResponse

from databases import connection
from modules.walletTransactions import post_entry

QR_TOKEN_TTL_SECONDS = 300
_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9_-]{8,40}$")


# ── Helpers ─────────────────────────────────────────────────────────────────

def _sp(proc: str, json_file: dict) -> dict:
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{proc}] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


def hash_key(device_key: str) -> str:
    return hashlib.sha256(device_key.encode()).hexdigest()


def new_device_key() -> str:
    return secrets.token_urlsafe(32)


def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _b64d(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def _qr_secret() -> bytes:
    secret = os.getenv("LAUNDRY_QR_SECRET", "")
    if not secret:
        raise RuntimeError("LAUNDRY_QR_SECRET no está configurado")
    return secret.encode()


def issue_qr_token(company_id: int, client_id: int, now: float = None) -> dict:
    """'v1.<payload>.<signature>' — payload {c: companyId, u: clientId, j: tokenId, e: exp}."""
    exp = int(now if now is not None else time.time()) + QR_TOKEN_TTL_SECONDS
    payload = _b64e(json.dumps({"c": company_id, "u": client_id, "j": secrets.token_hex(8), "e": exp},
                               separators=(",", ":")).encode())
    sig = _b64e(hmac.new(_qr_secret(), f"v1.{payload}".encode(), hashlib.sha256).digest())
    return {"qrToken": f"v1.{payload}.{sig}", "expiresAt": exp}


def verify_qr_token(token: str, now: float = None) -> dict:
    """Returns {companyId, clientId, tokenId} or raises ValueError(reason)."""
    parts = (token or "").split(".")
    if len(parts) != 3 or parts[0] != "v1":
        raise ValueError("token_malformed")
    expected = _b64e(hmac.new(_qr_secret(), f"v1.{parts[1]}".encode(), hashlib.sha256).digest())
    if not hmac.compare_digest(expected, parts[2]):
        raise ValueError("token_invalid")
    try:
        data = json.loads(_b64d(parts[1]))
        company_id, client_id, token_id, exp = int(data["c"]), int(data["u"]), str(data["j"]), int(data["e"])
    except (ValueError, KeyError, TypeError):
        raise ValueError("token_malformed")
    if exp < (now if now is not None else time.time()):
        raise ValueError("token_expired")
    return {"companyId": company_id, "clientId": client_id, "tokenId": token_id}


def _authenticate(device_id, device_key):
    """The device row (without keyHash) or a JSONResponse to return as-is."""
    try:
        device_id = int(device_id)
    except (TypeError, ValueError):
        return JSONResponse({"error": "device_unauthorized"}, status_code=401)
    device = _sp("sp_laundryDevices", {"laundryDevices": [{"action": 4, "deviceId": device_id}]})
    key_hash = device.pop("keyHash", None)
    if not key_hash or not device_key or not hmac.compare_digest(key_hash, hash_key(device_key)):
        return JSONResponse({"error": "device_unauthorized"}, status_code=401)
    if not int(device.get("isActive") or 0):
        return JSONResponse({"error": "device_inactive"}, status_code=403)
    return device


def _use_response(use: dict, device: dict) -> JSONResponse:
    authorized = use.get("status") == "authorized"
    body = {
        "authorized": authorized,
        "useId": use.get("useId"),
        "amountMXN": use.get("amountMXN"),
        "replayed": bool(use.get("replayed")),
    }
    if authorized:
        body.update(balanceAfter=use.get("balanceAfter"), cycleMinutes=device.get("cycleMinutes"))
    else:
        body["reason"] = use.get("reason")
    return JSONResponse(body, status_code=200 if authorized else 402)


# ── Device endpoints (X-Device-Id / X-Device-Key) ───────────────────────────

def heartbeat(device_id, device_key, payload: dict, client_ip: str = None):
    try:
        device = _authenticate(device_id, device_key)
        if isinstance(device, JSONResponse):
            return device
        rssi = payload.get("rssi")
        result = _sp("sp_laundryDevices", {"laundryDevices": [{
            "action": 5, "deviceId": device["deviceId"],
            "status": (payload.get("status") or None) and str(payload["status"])[:20],
            "firmwareVersion": (payload.get("firmwareVersion") or None) and str(payload["firmwareVersion"])[:30],
            "ip": client_ip, "rssi": rssi if isinstance(rssi, int) else None,
        }]})
        if result.get("error"):
            return JSONResponse(result, status_code=500)
        return JSONResponse({
            "ok": True, "serverTimeUtc": result.get("serverTimeUtc"),
            "priceMXN": result.get("priceMXN"), "cycleMinutes": result.get("cycleMinutes"),
        }, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def authorize(device_id, device_key, payload: dict):
    try:
        device = _authenticate(device_id, device_key)
        if isinstance(device, JSONResponse):
            return device

        request_id = str(payload.get("requestId") or "")
        if not _REQUEST_ID_RE.match(request_id):
            return JSONResponse({"error": "requestId inválido (8-40 caracteres: letras, números, - o _)"},
                                status_code=400)
        try:
            token = verify_qr_token(payload.get("qrToken"))
        except ValueError as e:
            return JSONResponse({"authorized": False, "reason": str(e)}, status_code=401)
        if token["companyId"] != device["companyId"]:
            return JSONResponse({"authorized": False, "reason": "token_wrong_company"}, status_code=401)

        use = _sp("sp_laundryDeviceUses", {"laundryDeviceUses": [{
            "action": 1, "deviceId": device["deviceId"], "companyId": device["companyId"],
            "clientId": token["clientId"], "requestId": request_id, "tokenId": token["tokenId"],
            "amountMXN": device["priceMXN"],
        }]})
        if use.get("error") in ("token_used", "request_conflict"):
            return JSONResponse({"authorized": False, "reason": use["error"]}, status_code=409)
        if use.get("error"):
            return JSONResponse(use, status_code=500)
        if use.get("status") != "pending":
            return _use_response(use, device)

        # Pending: first try, or a retry after a crash between open and settle.
        # The ledger key makes the debit happen at most once either way.
        entry = post_entry(
            company_id=device["companyId"], client_id=use["clientId"], entry_type="LAUNDRY_USAGE",
            direction="D", amount_mxn=float(use["amountMXN"]),
            idempotency_key=f"laundry:{device['deviceId']}:{request_id}",
            reference_type="laundryDeviceUse", reference_id=use["useId"],
            note=f"Lavandería: {device.get('name')}",
        )
        if entry.get("error") == "Saldo insuficiente":
            settle = {"status": "rejected", "reason": "insufficient_funds"}
        elif entry.get("error"):
            # Left pending: the ESP32 retries with the same requestId.
            return JSONResponse({"error": entry["error"]}, status_code=502)
        else:
            settle = {"status": "authorized", "ledgerEntryId": entry.get("entryId"),
                      "balanceAfter": entry.get("balanceAfter")}

        settled = _sp("sp_laundryDeviceUses", {"laundryDeviceUses": [{"action": 2, "useId": use["useId"], **settle}]})
        if settled.get("error"):
            return JSONResponse(settled, status_code=500)
        settled["replayed"] = use.get("replayed")
        return _use_response(settled, device)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


# ── App / admin endpoints ───────────────────────────────────────────────────

def qr_token(payload: dict):
    row = (payload.get("laundryDevices") or [{}])[0]
    try:
        company_id, client_id = int(row["companyId"]), int(row["clientId"])
    except (KeyError, TypeError, ValueError):
        return JSONResponse({"error": "companyId y clientId son requeridos"}, status_code=400)
    try:
        return JSONResponse(issue_qr_token(company_id, client_id), status_code=200)
    except RuntimeError as e:
        return JSONResponse({"error": str(e)}, status_code=503)


def laundry_devices_sp(payload: dict):
    """action 1 create / 3 rotate key: the plain deviceKey is returned once and only its hash is stored."""
    try:
        row = dict((payload.get("laundryDevices") or [{}])[0])
        action = int(row.get("action") or 0)
        if action not in (1, 2, 3):
            return JSONResponse({"error": "action debe ser 1 (crear), 2 (actualizar) o 3 (rotar llave)"},
                                status_code=400)
        row.pop("keyHash", None)
        device_key = None
        if action in (1, 3):
            device_key = new_device_key()
            row["keyHash"] = hash_key(device_key)
        result = _sp("sp_laundryDevices", {"laundryDevices": [row]})
        if result.get("error"):
            return JSONResponse(result, status_code=400)
        if device_key:
            result["deviceKey"] = device_key
        return JSONResponse(result, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def all_laundry_devices_sp(payload: dict):
    try:
        return JSONResponse(_sp("sp_laundryDevices_all", payload), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def all_laundry_device_uses_sp(payload: dict):
    try:
        return JSONResponse(_sp("sp_laundryDeviceUses_all", payload), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
