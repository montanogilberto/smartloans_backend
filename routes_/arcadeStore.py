from fastapi import APIRouter
from modules.arcadeStore import (
    arcade_chip_packs_all_sp, arcade_purchase_sp, arcade_purchases_all_sp,
    arcade_checkout_sp, arcade_confirm_sp, arcade_quick_buy_sp, arcade_saved_card_sp,
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
    "/arcade/savedCard",
    summary="Tarjeta guardada del cliente",
    description="""
Solo marca y ultimos 4, para pintar "Pagar con •••• 4242". El id del metodo de
pago NUNCA sale al cliente.

Body: { "arcadePurchases": [{ companyId, clientId }] }
Returns: { "card": { brand, last4, expiryMonth, expiryYear } | null }
""",
)
def arcade_saved_card(json: dict):
    return arcade_saved_card_sp(json)


@router.post(
    "/arcade/quickBuy",
    summary="Comprar fichas en un toque con la tarjeta guardada",
    description="""
Cobra off-session a la tarjeta que ya esta en savedPaymentMethods — la misma
que cobra las cuotas automaticas — y acredita las fichas. El dinero entra a la
cuenta de SmartLoans.

El PRECIO SALE DEL CATALOGO: el cliente elige que paquete, nunca cuanto paga.

Body: { "arcadePurchases": [{ companyId, clientId, packKey }] }
Returns: { status: 'credited'|'already_credited', chipsCredited, coinBalance,
           card: { brand, last4 } }

409 no_saved_card            -> usar /arcade/checkout con Payment Element
409 authentication_required  -> el banco pide 3DS; viene clientSecret para
                                retomar el MISMO cobro con Payment Element
402 card_declined / not_paid    503 verification_unavailable
""",
)
def arcade_quick_buy(json: dict):
    return arcade_quick_buy_sp(json)


@router.post(
    "/arcade/checkout",
    summary="Abrir cobro de fichas con Stripe (WEB)",
    description="""
Camino WEB. Stripe es la pasarela correcta en el navegador: la regla de Apple
(3.1.1) y Play Billing solo alcanzan al binario nativo, no a un sitio web. En
la app nativa se usa /arcade/purchase con IAP.

El PRECIO SALE DEL CATALOGO: el cliente elige que paquete, nunca cuanto paga.

Body: { "arcadePurchases": [{ companyId, clientId, packKey }] }
Returns: { clientSecret, paymentIntentId, amount, currency, chips }

503 verification_unavailable (Stripe sin configurar)   400 unknown_pack
""",
)
def arcade_checkout(json: dict):
    return arcade_checkout_sp(json)


@router.post(
    "/arcade/confirm",
    summary="Confirmar el cobro y acreditar las fichas (WEB)",
    description="""
Relee el PaymentIntent DESDE STRIPE y solo acredita si Stripe dice succeeded;
no se confia en que el navegador diga que ya pago. Ademas comprueba que el
cobro sea de ese cliente.

Es seguro reintentar: responde already_credited sin volver a abonar. El
webhook de Stripe hace lo mismo si el usuario cierra la pestana.

Body: { "arcadePurchases": [{ paymentIntentId, clientId }] }
Returns: { status: 'credited'|'already_credited', chipsCredited, coinBalance }

402 not_paid   403 not_your_purchase   502 stripe_error
""",
)
def arcade_confirm(json: dict):
    return arcade_confirm_sp(json)


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
