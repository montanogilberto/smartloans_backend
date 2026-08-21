from fastapi import APIRouter
from modules.arcadeStore import (
    arcade_chip_packs_all_sp, arcade_purchase_sp, arcade_purchases_all_sp,
)

router = APIRouter()


@router.post(
    "/all_arcadeChipPacks",
    summary="Catalogo de paquetes de fichas",
    description="""
Paquetes comprables. priceMXN es SOLO para pintar la tarjeta; el precio real,
en la moneda del usuario, lo da StoreKit / Play Billing.

Body: { "arcadeChipPacks": [{ "companyId": int }] }
Returns: { "arcadeChipPacks": ChipPack[] }
""",
)
def all_arcade_chip_packs(json: dict):
    return arcade_chip_packs_all_sp(json)


@router.post(
    "/arcade/purchase",
    summary="Acreditar fichas de una compra verificada",
    description="""
SENTIDO UNICO: dinero -> fichas. No existe la operacion inversa.

El cliente manda el comprobante que le dio la tienda; el backend lo VERIFICA
contra Apple o Google y solo entonces acredita. Nunca se confia en el cliente.

iOS:     { "arcadePurchases": [{ companyId, clientId, packKey, platform: "ios",
           productId, transactionId }] }
Android: { "arcadePurchases": [{ companyId, clientId, packKey, platform: "android",
           productId, purchaseToken }] }

Returns: { "status": "credited" | "already_credited", "chipsCredited": int,
           "coinBalance": int }

Reenviar un comprobante ya usado devuelve 200 already_credited con
chipsCredited = 0 — es un reintento legitimo cuando se cae la red, no un error,
y no vuelve a abonar (UX_arcadePurchases_tx lo garantiza).

400 missing_fields / bad_platform
402 product_mismatch / revoked / not_purchased / unknown_transaction
502 verification_failed      503 verification_unavailable (falta configurar la tienda)
""",
)
def arcade_purchase(json: dict):
    return arcade_purchase_sp(json)


@router.post(
    "/all_arcadePurchases",
    summary="Historial de compras de fichas",
    description="""
Body: { "arcadePurchases": [{ "companyId": int, "clientId": int, "top"?: int }] }
Returns: { "arcadePurchases": Purchase[] }
""",
)
def all_arcade_purchases(json: dict):
    return arcade_purchases_all_sp(json)
