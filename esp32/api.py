# Llamadas al backend de GMO Laundry.

import time
import os
import binascii

import config as C
import hw
import net


def heartbeat(running):
    """Devuelve la respuesta del servidor (con la lista de ciclos) o None si falló."""
    status, data = net.post("/laundryDevices/heartbeat", {
        "status": "running" if running else "idle",
    })
    if status == 200:
        print("heartbeat OK;", len(data.get("cycles") or []), "ciclos")
        return data
    print("heartbeat falló:", status, data)
    return None


def _new_request_id():
    return binascii.hexlify(os.urandom(16)).decode()


def authorize(client_qr, choice_id):
    """Devuelve (resultado, data). Un requestId por cobro, reutilizado en todos
    los reintentos: el servidor cobra una sola vez."""
    body = {"requestId": _new_request_id(), "clientQr": client_qr,
            "productOptionChoiceId": choice_id}
    delay = 1
    for attempt in range(1, C.AUTH_MAX_TRIES + 1):
        net.ensure_wifi()
        status, data = net.post("/laundryDevices/authorize", body)
        print("authorize intento", attempt, "->", status, data)

        if status == 200 and data.get("authorized"):
            return "ok", data
        if status == 402:
            return "sin_saldo", data
        if status == 409:
            return "conflicto", data
        if status in (400, 401, 403, 404, 410):
            return "rechazado", data
        # None (red), 500, 502, 503...: reintentar con el MISMO requestId
        hw.feed()
        time.sleep(delay)
        delay = min(delay * 2, 8)
    return "sin_respuesta", {}
