"""
GMO Laundry — ESP32 machine controllers.

SQL: sql/migrations/2026-10-18_laundry_devices.sql.

Flow of one machine use:
  1. Each client has a fixed QR: 'GMO1.<companyId>.<clientId>.<signature>'
     (POST /laundryDevices/clientQr gives the text; the app draws it). A plain
     clientId is NOT accepted — anyone could print someone else's number.
  2. The machine's screen lists the cycles the heartbeat returned (the priced
     productOptionChoices of its product: 1002 lavado / 1003 secado); the client
     picks one and scans their QR.
  3. The ESP32 calls POST /laundryDevices/authorize with its own X-Device-Id /
     X-Device-Key headers, a requestId it keeps across retries, the QR text and
     the chosen productOptionChoiceId.
  4. Here: check the device key and the QR signature/company, price the cycle
     from the catalog (it must belong to this machine's product), open the use
     (idempotent on deviceId + requestId), debit that price as LAUNDRY_USAGE in
     walletTransactions (idempotent on the same key), settle.
  5. The ESP32 only switches the machine on when authorized = true.

The device never sends an amount. A device without productId charges its
fixed laundryDevices.priceMXN and takes no cycle.
"""

import base64
import hashlib
import hmac
import json
import os
import re
import secrets

from fastapi.responses import JSONResponse

from databases import connection
from modules.walletTransactions import post_entry

CLIENT_QR_PREFIX = "GMO1"
_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9_-]{8,40}$")
_MINUTES_RE = re.compile(r"(\d+)\s*min", re.IGNORECASE)


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


def _qr_secret() -> bytes:
    secret = os.getenv("LAUNDRY_QR_SECRET", "")
    if not secret:
        raise RuntimeError("LAUNDRY_QR_SECRET no está configurado")
    return secret.encode()


def _client_qr_signature(company_id: int, client_id: int) -> str:
    msg = f"{CLIENT_QR_PREFIX}.{company_id}.{client_id}".encode()
    return _b64e(hmac.new(_qr_secret(), msg, hashlib.sha256).digest())[:22]   # 132 bits


def client_qr_text(company_id: int, client_id: int) -> str:
    """The fixed QR of one client: 'GMO1.<companyId>.<clientId>.<signature>'."""
    return f"{CLIENT_QR_PREFIX}.{company_id}.{client_id}.{_client_qr_signature(company_id, client_id)}"


def verify_client_qr(text: str) -> dict:
    """Returns {companyId, clientId} or raises ValueError(reason)."""
    parts = (text or "").strip().split(".")
    if len(parts) != 4 or parts[0] != CLIENT_QR_PREFIX:
        raise ValueError("qr_malformed")
    try:
        company_id, client_id = int(parts[1]), int(parts[2])
    except ValueError:
        raise ValueError("qr_malformed")
    if not hmac.compare_digest(_client_qr_signature(company_id, client_id), parts[3]):
        raise ValueError("qr_invalid")
    return {"companyId": company_id, "clientId": client_id}


def cycle_minutes(choice_name, device: dict) -> int:
    """'50 Min' -> 50 (secado); cycles without minutes in the name use the device's cycleMinutes."""
    match = _MINUTES_RE.search(choice_name or "")
    return int(match.group(1)) if match else device.get("cycleMinutes")


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
        "choiceName": use.get("choiceName"),
        "replayed": bool(use.get("replayed")),
    }
    if authorized:
        body.update(balanceAfter=use.get("balanceAfter"), cycleMinutes=cycle_minutes(use.get("choiceName"), device))
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
        cycles = _sp("sp_laundryDevices", {"laundryDevices": [{"action": 7, "deviceId": device["deviceId"]}]})
        return JSONResponse({
            "ok": True, "serverTimeUtc": result.get("serverTimeUtc"), "productId": result.get("productId"),
            "priceMXN": result.get("priceMXN"), "cycleMinutes": result.get("cycleMinutes"),
            "cycles": [{**c, "cycleMinutes": cycle_minutes(c.get("name"), device)}
                       for c in cycles.get("cycles") or []],
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
            client = verify_client_qr(payload.get("clientQr"))
        except ValueError as e:
            return JSONResponse({"authorized": False, "reason": str(e)}, status_code=401)
        if client["companyId"] != device["companyId"]:
            return JSONResponse({"authorized": False, "reason": "qr_wrong_company"}, status_code=401)
        choice = payload.get("productOptionChoiceId")
        if choice is not None and not isinstance(choice, int):
            return JSONResponse({"error": "productOptionChoiceId debe ser entero"}, status_code=400)

        price = _sp("sp_laundryDevices", {"laundryDevices": [{
            "action": 6, "deviceId": device["deviceId"], "productOptionChoiceId": choice,
        }]})
        if price.get("error") == "choice_not_for_device":
            return JSONResponse({"authorized": False, "reason": "choice_not_for_device"}, status_code=400)
        if price.get("error"):
            return JSONResponse(price, status_code=500)

        use = _sp("sp_laundryDeviceUses", {"laundryDeviceUses": [{
            "action": 1, "deviceId": device["deviceId"], "companyId": device["companyId"],
            "clientId": client["clientId"], "requestId": request_id,
            "amountMXN": price["priceMXN"], "productOptionChoiceId": price.get("productOptionChoiceId"),
            "choiceName": price.get("choiceName"),
        }]})
        if use.get("error") == "request_conflict":
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
            note=f"Lavandería: {device.get('name')}" + (f" · {use['choiceName']}" if use.get("choiceName") else ""),
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

def client_qr(payload: dict):
    """The text the app turns into the client's fixed QR."""
    row = (payload.get("laundryDevices") or [{}])[0]
    try:
        company_id, client_id = int(row["companyId"]), int(row["clientId"])
    except (KeyError, TypeError, ValueError):
        return JSONResponse({"error": "companyId y clientId son requeridos"}, status_code=400)
    try:
        return JSONResponse({"clientQr": client_qr_text(company_id, client_id)}, status_code=200)
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


# ── Batch: regenerate every client's fixed QR ───────────────────────────────

REGENERATE_MAX_PER_CALL = 500


def client_qr_png(text: str) -> bytes:
    import io
    import segno
    buf = io.BytesIO()
    segno.make(text, error="m").save(buf, kind="png", scale=10, border=4)
    return buf.getvalue()


def _save_client_qr(company_id: int, client_id: int, stamp: str) -> str:
    """PNG of the signed QR -> Blob Storage (same layout as /clients/upload-qr) -> clients.qrBlobUrl."""
    from modules.clients import _upload_bytes_to_blob
    from modules.clientFaceRecognitions import client_blob_path

    png = client_qr_png(client_qr_text(company_id, client_id))
    blob_path = client_blob_path(client_id, "qr", f"qr_gmo1_{stamp}_{secrets.token_hex(4)}.png")
    url = _upload_bytes_to_blob(png, blob_path, "image/png", {
        "clientId": str(client_id), "companyId": str(company_id), "type": "qr", "format": CLIENT_QR_PREFIX,
    })
    result = _sp("sp_clients_qr", {"clients": [{"clientId": client_id, "companyId": company_id, "qrBlobUrl": url}]})
    if result.get("error"):
        raise RuntimeError(result["error"])
    return url


def regenerate_client_qrs(payload: dict):
    """One page of clients per call: repeat with afterClientId = nextAfterClientId until it is null."""
    from datetime import datetime

    row = (payload.get("clients") or [{}])[0]
    try:
        company_id = int(row["companyId"])
        limit = min(int(row.get("top") or 200), REGENERATE_MAX_PER_CALL)
        after = int(row.get("afterClientId") or 0)
        client_ids = [int(c) for c in row["clientIds"]] if row.get("clientIds") else None
    except (KeyError, TypeError, ValueError):
        return JSONResponse({"error": "companyId es requerido; clientIds debe ser lista de enteros"}, status_code=400)
    dry_run = bool(row.get("dryRun"))
    try:
        _qr_secret()
    except RuntimeError as e:
        return JSONResponse({"error": str(e)}, status_code=503)

    try:
        listed = _sp("sp_laundryClientQrs_list", {"clients": [{
            "companyId": company_id, "afterClientId": after, "top": limit, "clientIds": client_ids,
        }]})
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
    ids = [c["clientId"] for c in listed.get("clients") or []]

    stamp = datetime.utcnow().strftime("%Y%m%d%H%M%S")
    updated, failed = [], []
    for client_id in ids:
        if dry_run:
            continue
        try:
            _save_client_qr(company_id, client_id, stamp)
            updated.append(client_id)
        except Exception as e:
            failed.append({"clientId": client_id, "error": str(e)})
    print(f"[laundryDevices] regenerateClientQrs company={company_id} listed={len(ids)} "
          f"updated={len(updated)} failed={len(failed)} dryRun={dry_run}")

    return JSONResponse({
        "companyId": company_id, "dryRun": dry_run, "listed": len(ids),
        "updated": len(updated), "failed": failed,
        "nextAfterClientId": ids[-1] if len(ids) == limit and not client_ids else None,
    }, status_code=200)
