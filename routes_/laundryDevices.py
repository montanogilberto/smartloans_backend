from fastapi import APIRouter, Depends, Header, Request

from modules.laundryDevices import (
    heartbeat, authorize, client_qr, laundry_devices_sp,
    all_laundry_devices_sp, all_laundry_device_uses_sp, regenerate_client_qrs,
)
from security.worker_key import require_worker_key

router = APIRouter(tags=["Laundry Devices"])


@router.post(
    "/laundryDevices/heartbeat",
    summary="ESP32: estoy vivo",
    description="""
Lo llama el ESP32 cada ~60 s. Actualiza lastSeenAtUtc y devuelve los ciclos
que la pantalla de la máquina debe mostrar (opciones con precio del producto
de la máquina).

Headers: X-Device-Id: int, X-Device-Key: str
Body: { "status"?: "idle|running|error", "firmwareVersion"?: str, "rssi"?: int }
Returns: { ok, serverTimeUtc, productId, priceMXN, cycleMinutes,
           cycles: [{ productOptionChoiceId, name, priceMXN, cycleMinutes }] }
priceMXN es null cuando la máquina cobra por ciclo (productId).

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
Valida la llave del dispositivo y el QR fijo firmado del cliente, y debita de
su saldo (walletTransactions, LAUNDRY_USAGE) el precio del ciclo que eligió en
la pantalla — una productOptionChoice del producto de la máquina — o el
priceMXN fijo si la máquina no tiene productId. El ESP32 nunca manda el monto.
cycleMinutes sale del nombre del ciclo ("50 Min") o del de la máquina.

IDEMPOTENTE: genera requestId una vez por lectura de QR y reúsalo en cada
reintento — la respuesta es la misma y el cobro ocurre una sola vez.

Headers: X-Device-Id: int, X-Device-Key: str
Body: { "requestId": str (8-40, [A-Za-z0-9_-]), "clientQr": str, "productOptionChoiceId": int }
Returns 200: { authorized: true, useId, amountMXN, choiceName, balanceAfter, cycleMinutes, replayed }
        402: { authorized: false, useId, amountMXN, choiceName, reason: "insufficient_funds", replayed }

400 choice_not_for_device (el ciclo no es de esta máquina, p. ej. un ciclo de
    secado mandado por la lavadora)
401 device_unauthorized / qr_invalid / qr_malformed / qr_wrong_company
403 device_inactive   409 request_conflict (mismo requestId con otro cliente o ciclo)
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
    "/laundryDevices/clientQr",
    summary="App: texto del QR fijo del cliente",
    description="""
El QR de cada cliente para las máquinas: 'GMO1.<companyId>.<clientId>.<firma>'.
No vence; la firma (HMAC con LAUNDRY_QR_SECRET) impide fabricar el QR de otro
cliente. Un QR que sólo trae el clientId NO sirve para cobrar.

Body: { "laundryDevices": [{ "companyId": int, "clientId": int }] }
Returns: { clientQr: str }
""",
)
def laundry_device_client_qr(json: dict):
    return client_qr(json)


@router.post(
    "/laundryDevices",
    summary="Alta, edición y rotación de llave de dispositivos",
    description="""
action 1 crear:  { companyId, name, machineType: "washer|dryer", productId | priceMXN, cycleMinutes?, branchId? }
                 productId = cobra el ciclo elegido en la app; priceMXN = precio fijo.
action 2 editar: { deviceId, companyId, name?, productId?, priceMXN?, cycleMinutes?, isActive?, branchId? }
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


@router.post(
    "/laundryDevices/regenerateClientQrs",
    summary="Lote: regenerar el QR fijo firmado de los clientes",
    dependencies=[Depends(require_worker_key)],
    description="""
Para cada cliente activo de la compañía genera el QR 'GMO1.<companyId>.<clientId>.<firma>',
sube el PNG a Blob Storage (misma ruta que /clients/upload-qr) y actualiza
clients.qrBlobUrl. La app muestra el nuevo QR sin cambios.

Header: X-Worker-Key (WORKER_KEY del App Service).
Body: { "clients": [{ "companyId": int, "clientIds"?: [int], "afterClientId"?: int,
        "top"?: int (máx 500), "dryRun"?: bool }] }
Returns: { listed, updated, failed: [{ clientId, error }], nextAfterClientId }

Por páginas: repite con afterClientId = nextAfterClientId hasta que sea null.
dryRun = true sólo cuenta, no sube ni actualiza nada. Se puede repetir sin
riesgo: el texto del QR de un cliente siempre es el mismo.
""",
)
def laundry_regenerate_client_qrs(json: dict):
    return regenerate_client_qrs(json)
