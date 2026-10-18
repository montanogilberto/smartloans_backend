from fastapi import APIRouter, Header, Request

from modules.laundryDevices import (
    heartbeat, authorize, qr_token, laundry_devices_sp,
    all_laundry_devices_sp, all_laundry_device_uses_sp,
)

router = APIRouter(tags=["Laundry Devices"])


@router.post(
    "/laundryDevices/heartbeat",
    summary="ESP32: estoy vivo",
    description="""
Lo llama el ESP32 cada ~60 s. Actualiza lastSeenAtUtc y devuelve el precio y
el ciclo vigentes de su máquina.

Headers: X-Device-Id: int, X-Device-Key: str
Body: { "status"?: "idle|running|error", "firmwareVersion"?: str, "rssi"?: int }
Returns: { ok, serverTimeUtc, priceMXN, cycleMinutes }

401 device_unauthorized   403 device_inactive
""",
)
def laundry_device_heartbeat(
    request: Request,
    json: dict = None,
    x_device_id: str | None = Header(default=None),
    x_device_key: str | None = Header(default=None),
):
    client_ip = request.client.host if request.client else None
    return heartbeat(x_device_id, x_device_key, json or {}, client_ip)


@router.post(
    "/laundryDevices/authorize",
    summary="ESP32: cobrar un uso con el QR del cliente",
    description="""
Valida la llave del dispositivo y el QR firmado, y debita priceMXN de la
máquina del saldo del cliente (walletTransactions, LAUNDRY_USAGE). El ESP32
nunca manda el monto.

IDEMPOTENTE: genera requestId una vez por lectura de QR y reúsalo en cada
reintento — la respuesta es la misma y el cobro ocurre una sola vez.

Headers: X-Device-Id: int, X-Device-Key: str
Body: { "requestId": str (8-40, [A-Za-z0-9_-]), "qrToken": str }
Returns 200: { authorized: true, useId, amountMXN, balanceAfter, cycleMinutes, replayed }
        402: { authorized: false, useId, amountMXN, reason: "insufficient_funds", replayed }

401 device_unauthorized / token_invalid / token_expired / token_malformed / token_wrong_company
403 device_inactive   409 token_used / request_conflict
502 el ledger falló: reintenta con el MISMO requestId
""",
)
def laundry_device_authorize(
    json: dict,
    x_device_id: str | None = Header(default=None),
    x_device_key: str | None = Header(default=None),
):
    return authorize(x_device_id, x_device_key, json)


@router.post(
    "/laundryDevices/qrToken",
    summary="App: QR de un solo uso para pagar una máquina",
    description="""
Token firmado que la app muestra como QR. Vence en 5 minutos y sólo puede
respaldar un cobro autorizado.

Body: { "laundryDevices": [{ "companyId": int, "clientId": int }] }
Returns: { qrToken: str, expiresAt: int (epoch s) }
""",
)
def laundry_device_qr_token(json: dict):
    return qr_token(json)


@router.post(
    "/laundryDevices",
    summary="Alta, edición y rotación de llave de dispositivos",
    description="""
action 1 crear:  { companyId, name, machineType: "washer|dryer", priceMXN, cycleMinutes?, branchId? }
action 2 editar: { deviceId, companyId, name?, priceMXN?, cycleMinutes?, isActive?, branchId? }
action 3 rotar llave: { deviceId, companyId }

Crear y rotar devuelven deviceKey UNA sola vez — grábala en el ESP32; el
servidor sólo guarda su hash.

Body: { "laundryDevices": [{ "action": int, ... }] }
""",
)
def laundry_devices(json: dict):
    return laundry_devices_sp(json)


@router.post(
    "/all_laundryDevices",
    summary="Dispositivos de la compañía",
    description="""Body: { "laundryDevices": [{ "companyId": int }] }
Returns: { laundryDevices: [{ ..., lastSeenAtUtc, isOnline }] }  — isOnline = heartbeat en los últimos 3 min.""",
)
def all_laundry_devices(json: dict):
    return all_laundry_devices_sp(json)


@router.post(
    "/all_laundryDeviceUses",
    summary="Historial de usos de máquinas",
    description="""Body: { "laundryDeviceUses": [{ "companyId": int, "deviceId"?: int, "clientId"?: int, "top"?: int }] }""",
)
def all_laundry_device_uses(json: dict):
    return all_laundry_device_uses_sp(json)
