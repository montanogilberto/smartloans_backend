"""
arcadeStore — compra de fichas con dinero real.

SENTIDO UNICO: dinero -> fichas. NUNCA fichas -> dinero. Sin ruta de canje no
hay premio de valor economico, y sin premio el modelo es "casino social" y no
casa de apuestas — que es lo que lo mantiene fuera del permiso SEGOB.

EL COBRO NO PASA POR STRIPE. Apple (guia 3.1.1) y Google exigen StoreKit /
Play Billing para bienes digitales consumidos dentro de la app; cobrar con
Stripe hace que rechacen la build. Aqui llega una compra que la TIENDA ya
cobro, y este modulo la verifica CONTRA LOS SERVIDORES DE LA TIENDA antes de
acreditar nada.

NUNCA se confia en el cliente. Un cliente que dice "ya pague" no acredita
fichas: se pide el recibo, se valida contra Apple/Google y solo entonces se
llama a sp_arcadePurchases_credit. Falla cerrado — si faltan credenciales,
se RECHAZA la compra en vez de regalar fichas.
"""

import json
import os
import secrets
import time
import uuid

import httpx
import jwt
from fastapi.responses import JSONResponse

from databases import connection
from observability import log_audit, log_workflow_step, timed_integration

WORKFLOW = "arcade_store"

APPLE_PROD = "https://api.storekit.itunes.apple.com/inApps/v1/transactions/"
APPLE_SANDBOX = "https://api.storekit-sandbox.itunes.apple.com/inApps/v1/transactions/"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_PURCHASES = (
    "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
    "/{package}/purchases/products/{product}/tokens/{token}"
)


def _conn():
    return connection()


def _exec_sp(sp_name: str, payload: dict) -> dict:
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{sp_name}] @pjsonfile = %s", (json.dumps(payload),))
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    finally:
        if conn:
            conn.close()


class VerificationError(Exception):
    """El recibo no es valido, o no se pudo comprobar. Nunca se acredita."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


# ---------------------------------------------------------------------------
# Apple — App Store Server API
# ---------------------------------------------------------------------------

def _apple_client_token() -> str:
    """
    JWT ES256 firmado con la llave .p8 de App Store Connect. Dura poco a
    proposito: se firma uno por peticion en vez de cachearlo.
    """
    key = os.getenv("APPLE_IAP_PRIVATE_KEY", "").replace("\\n", "\n").strip()
    key_id = os.getenv("APPLE_IAP_KEY_ID", "")
    issuer = os.getenv("APPLE_IAP_ISSUER_ID", "")
    bundle = os.getenv("APPLE_IAP_BUNDLE_ID", "")

    if not (key and key_id and issuer and bundle):
        raise VerificationError(
            "verification_unavailable",
            "La verificacion con App Store no esta configurada",
        )

    now = int(time.time())
    return jwt.encode(
        {
            "iss": issuer,
            "iat": now,
            "exp": now + 600,
            "aud": "appstoreconnect-v1",
            "bid": bundle,
        },
        key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def _verify_apple(product_id: str, transaction_id: str) -> dict:
    """
    Consulta la transaccion en Apple y devuelve sus datos ya normalizados.

    Se prueba produccion y, si Apple no la conoce (404), sandbox: una build de
    TestFlight cobra contra sandbox y con un solo entorno las pruebas fallarian
    sin motivo aparente.
    """
    token = _apple_client_token()
    headers = {"Authorization": f"Bearer {token}"}

    payload, environment = None, None
    with httpx.Client(timeout=20) as client:
        for base, env in ((APPLE_PROD, "production"), (APPLE_SANDBOX, "sandbox")):
            with timed_integration("apple_storekit", "get_transaction") as span:
                res = client.get(base + transaction_id, headers=headers)
                span.http_status = res.status_code
            if res.status_code == 200:
                # El JWS viene de Apple por TLS, asi que se decodifica el cuerpo
                # sin re-verificar la firma: la autenticidad la da el canal.
                signed = res.json().get("signedTransactionInfo", "")
                payload = jwt.decode(signed, options={"verify_signature": False})
                environment = payload.get("environment", env)
                break
            if res.status_code != 404:
                raise VerificationError(
                    "verification_failed",
                    f"App Store respondio {res.status_code}",
                )

    if payload is None:
        raise VerificationError("unknown_transaction", "Apple no reconoce esa compra")

    if payload.get("productId") != product_id:
        raise VerificationError("product_mismatch", "El recibo es de otro producto")
    if payload.get("revocationDate"):
        raise VerificationError("revoked", "Esa compra fue reembolsada")

    price = payload.get("price")
    return {
        "storeTransactionId": str(payload.get("transactionId")),
        "storeOriginalTransactionId": str(payload.get("originalTransactionId") or ""),
        # Apple entrega el precio en milesimas de unidad.
        "priceCharged": round(price / 1000, 2) if isinstance(price, (int, float)) else None,
        "currency": payload.get("currency"),
        "environment": environment,
    }


# ---------------------------------------------------------------------------
# Google Play — Android Publisher API
# ---------------------------------------------------------------------------

def _google_access_token() -> str:
    """
    Token OAuth2 a partir de la cuenta de servicio. Se firma el JWT a mano con
    PyJWT en vez de traer google-auth: es una dependencia menos para un unico
    intercambio de token.
    """
    email = os.getenv("GOOGLE_PLAY_SA_EMAIL", "")
    key = os.getenv("GOOGLE_PLAY_SA_PRIVATE_KEY", "").replace("\\n", "\n").strip()

    if not (email and key):
        raise VerificationError(
            "verification_unavailable",
            "La verificacion con Google Play no esta configurada",
        )

    now = int(time.time())
    assertion = jwt.encode(
        {
            "iss": email,
            "scope": "https://www.googleapis.com/auth/androidpublisher",
            "aud": GOOGLE_TOKEN_URL,
            "iat": now,
            "exp": now + 3600,
        },
        key,
        algorithm="RS256",
    )

    with httpx.Client(timeout=20) as client:
        with timed_integration("google_play", "oauth_token") as span:
            res = client.post(GOOGLE_TOKEN_URL, data={
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": assertion,
            })
            span.http_status = res.status_code
    if res.status_code != 200:
        raise VerificationError("verification_failed", "Google rechazo las credenciales")
    return res.json()["access_token"]


def _verify_google(product_id: str, purchase_token: str) -> dict:
    package = os.getenv("GOOGLE_PLAY_PACKAGE_NAME", "")
    if not package:
        raise VerificationError(
            "verification_unavailable",
            "La verificacion con Google Play no esta configurada",
        )

    token = _google_access_token()
    url = GOOGLE_PURCHASES.format(package=package, product=product_id, token=purchase_token)

    with httpx.Client(timeout=20) as client:
        with timed_integration("google_play", "get_purchase") as span:
            res = client.get(url, headers={"Authorization": f"Bearer {token}"})
            span.http_status = res.status_code

    if res.status_code == 404:
        raise VerificationError("unknown_transaction", "Google no reconoce esa compra")
    if res.status_code != 200:
        raise VerificationError("verification_failed", f"Google Play respondio {res.status_code}")

    data = res.json()
    # purchaseState: 0 = comprada, 1 = cancelada, 2 = pendiente.
    if data.get("purchaseState") != 0:
        raise VerificationError("not_purchased", "Esa compra no esta confirmada")

    return {
        # orderId es unico por compra; si faltara, el token ya lo es.
        "storeTransactionId": data.get("orderId") or purchase_token,
        "storeOriginalTransactionId": data.get("orderId"),
        "priceCharged": None,   # products.get no devuelve precio
        "currency": data.get("regionCode"),
        "environment": "sandbox" if data.get("purchaseType") == 0 else "production",
    }


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

def _first(json_file: dict, key: str) -> dict:
    items = json_file.get(key) or [{}]
    return items[0] if isinstance(items, list) and items else {}


def arcade_chip_packs_all_sp(json_file: dict):
    """
    Catalogo de paquetes. `priceMXN` es SOLO para pintar la tarjeta antes de
    que responda la tienda; el precio real, en la moneda del usuario, lo da
    StoreKit / Play Billing y nunca sale de aqui.
    """
    try:
        data = _exec_sp("sp_arcadeChipPacks_all", json_file)
        if "error" in data:
            return JSONResponse(content=data, status_code=500)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def arcade_purchase_sp(json_file: dict):
    """
    Acredita una compra de fichas DESPUES de verificarla con la tienda.

    El cliente manda el comprobante que le dio StoreKit / Play Billing; este
    modulo lo valida contra Apple o Google y solo entonces abona. Falla
    cerrado: cualquier duda -> no se acreditan fichas.
    """
    body = _first(json_file, "arcadePurchases")
    company_id = body.get("companyId")
    client_id = body.get("clientId")
    pack_key = body.get("packKey")
    platform = (body.get("platform") or "").lower()
    product_id = body.get("productId")
    # iOS manda transactionId; Android manda purchaseToken.
    receipt = body.get("transactionId") or body.get("purchaseToken")

    if not (company_id and client_id and pack_key and product_id and receipt):
        return JSONResponse(
            content={"error": "missing_fields", "message": "Faltan datos de la compra"},
            status_code=400,
        )
    # 'web' NO entra aqui: el cobro por navegador va con Stripe, por
    # /arcade/checkout + /arcade/confirm. Este endpoint es solo para recibos
    # de tienda nativa.
    if platform not in ("ios", "android"):
        return JSONResponse(
            content={"error": "bad_platform",
                     "message": "Usa /arcade/checkout para comprar desde el navegador"},
            status_code=400,
        )

    # Un id de intento para poder seguir el rastro entre logs sin registrar el
    # recibo, que es un secreto reutilizable (CLAUDE.md §9: nada de secretos).
    attempt = uuid.uuid4().hex[:12]

    try:
        with timed_integration("iap", f"verify_{platform}"):
            verified = (
                _verify_apple(product_id, receipt) if platform == "ios"
                else _verify_google(product_id, receipt)
            )
    except VerificationError as err:
        log_workflow_step(
            "Chip Purchase Rejected", workflow_name=WORKFLOW, action=platform,
            status="FAILURE", entity="arcadePurchases",
            message=f"[{attempt}] {err.code} — pack {pack_key}",
        )
        # 402: se cobro (o eso dice el cliente) pero no se pudo comprobar.
        status = 503 if err.code == "verification_unavailable" else 402
        return JSONResponse(
            content={"error": err.code, "message": err.message}, status_code=status,
        )
    except Exception as e:
        log_workflow_step(
            "Chip Purchase Error", workflow_name=WORKFLOW, action=platform,
            status="FAILURE", entity="arcadePurchases", message=f"[{attempt}] {type(e).__name__}",
        )
        return JSONResponse(
            content={"error": "verification_failed",
                     "message": "No se pudo verificar la compra con la tienda"},
            status_code=502,
        )

    credited = _exec_sp("sp_arcadePurchases_credit", {"arcadePurchases": [{
        "companyId": company_id,
        "clientId": client_id,
        "packKey": pack_key,
        "platform": platform,
        "productId": product_id,
        **verified,
    }]})

    if "error" in credited:
        return JSONResponse(content=credited, status_code=500)

    if credited.get("status") == "already_credited":
        # Reintento legitimo del cliente: no es error y no vuelve a abonar.
        return JSONResponse(content={
            "status": "already_credited",
            "chipsCredited": 0,
            "coinBalance": credited.get("coinBalance"),
        }, status_code=200)

    log_workflow_step(
        "Chip Purchase Credited", workflow_name=WORKFLOW, action=platform,
        entity="arcadePurchases", entity_id=credited.get("purchaseId"),
        message=f"[{attempt}] pack {pack_key} — {credited.get('chipsCredited')} fichas",
    )
    log_audit("arcadePurchases", credited.get("purchaseId"), "chipsCredited",
              None, credited.get("chipsCredited"), action="INSERT")

    gross = (intent.get("amount_received") or intent.get("amount") or 0) / 100.0
    fee, net, pct = _stripe_fee(intent, gross)
    _issue_ticket(credited, company_id=meta.get("companyId"), client_id=client_id,
                  pack=_pack_row(meta.get("packKey") or ""),
                  amount_cents=int(round(gross * 100)),
                  currency=(intent.get("currency") or "mxn").upper(),
                  reference=intent_id, fee=fee, net=net, fee_pct=pct)

    return JSONResponse(content={
        "status": "credited",
        "folio": credited.get("folio"),
        "chipsCredited": credited.get("chipsCredited"),
        "coinBalance": credited.get("coinBalance"),
    }, status_code=200)


def arcade_purchases_all_sp(json_file: dict):
    """Historial de compras del jugador."""
    try:
        data = _exec_sp("sp_arcadePurchases_all", json_file)
        if "error" in data:
            return JSONResponse(content=data, status_code=500)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------------------------
# Stripe — compra de fichas en WEB
# ---------------------------------------------------------------------------
# Stripe SI es la pasarela correcta en el navegador: Apple y Google no mandan
# sobre un sitio web, su regla (guia 3.1.1 / Play Billing) solo alcanza al
# binario nativo. Por eso el arcade cobra con Stripe en web y con IAP en la
# app; no es un rodeo, son dos jurisdicciones distintas.
#
# Esta compra NO toca walletTransactions ni el ledger de dinero real: es
# INGRESO del negocio a cambio de un bien virtual, no saldo del usuario. Por
# eso se crea un PaymentIntent propio en vez de reusar create_payment_intent(),
# que sí escribe en el ledger de la billetera.
#
# El IMPORTE SALE DE LA BASE, nunca del cliente. Si el navegador pudiera
# mandar el monto, cualquiera compraria el paquete grande por un peso.
# ---------------------------------------------------------------------------

import stripe  # noqa: E402  (se agrupa con el resto del bloque Stripe)

stripe.api_key = os.getenv("STRIPE_SECRET_KEY", "")

ARCADE_INTENT_KIND = "arcade_chips"


def _stripe_ready() -> bool:
    return bool(stripe.api_key) and not stripe.api_key.startswith("sk_test_YOUR")


def _stripe_environment() -> str:
    return "test" if stripe.api_key.startswith("sk_test") else "production"


def _pack_amount(pack: dict, chips: int | None) -> tuple[int, int, str | None]:
    """
    (centavos, fichas, error) de una compra.

    Para el paquete 'custom' el precio sale de regla de tres sobre la TARIFA
    guardada (`chips` fichas cuestan `priceMXN`), no de lo que mande el
    cliente: el navegador elige CUANTAS fichas, jamas cuanto paga.
    """
    if pack.get("isCustom") == "1":
        lo = int(pack.get("minChips") or 0)
        hi = int(pack.get("maxChips") or 0)
        if chips is None:
            return 0, 0, "chips_required"
        chips = int(chips)
        if chips < lo or chips > hi:
            return 0, 0, "chips_out_of_range"
        rate = float(pack["priceMXN"]) / float(pack["chips"])   # $ por ficha
        return int(round(chips * rate * 100)), chips, None

    total = int(pack["chips"]) + int(pack.get("bonusChips") or 0)
    return int(round(float(pack["priceMXN"]) * 100)), total, None


def _stripe_fee(intent, gross_mxn: float):
    """
    (comision, neto, etiqueta%) reales del cargo.

    Reusa el calculo de stripe_payments, que lee el balance_transaction y solo
    cae a la formula publicada si no esta disponible (CLAUDE.md §7).
    """
    try:
        from modules.stripe_payments import (
            _stripe_fee_and_net_mxn, _STRIPE_MX_PCT, _STRIPE_MX_FIXED, _IVA,
        )
        fee, net = _stripe_fee_and_net_mxn(intent, gross_mxn)
        etiqueta = f"{_STRIPE_MX_PCT * 100:.1f}% + ${_STRIPE_MX_FIXED:.0f} + IVA {_IVA * 100:.0f}%"
        return fee, net, etiqueta
    except Exception as e:
        print(f"[arcadeStore] no se pudo calcular la comision: {type(e).__name__}: {e}")
        return None, None, None


def _issue_ticket(credited: dict, *, company_id, client_id, pack: dict,
                  amount_cents: int, currency: str, reference: str,
                  fee=None, net=None, fee_pct=None) -> None:
    """Dispara el ticket (HTML + ADLS + correo) sin bloquear la compra."""
    try:
        from modules.arcadeTicket import issue_ticket_async
        from modules.stripe_payments import _client_contact

        def _store(purchase_id, url, sent):
            _exec_sp("sp_arcadePurchases_receipt", {"arcadePurchases": [{
                "purchaseId": purchase_id,
                "receiptUrl": url,
                "emailSent": "1" if sent else "0",
            }]})

        issue_ticket_async(
            {
                "purchaseId": credited.get("purchaseId"),
                "folio": credited.get("folio") or "—",
                "companyId": company_id,
                "chips": credited.get("chipsCredited") or 0,
                "amount": amount_cents / 100.0,
                "currency": currency,
                "concepto": pack.get("name") or "Fichas de arcade",
                "reference": reference,
                "feeMXN": fee,
                "netMXN": net,
                "feePct": fee_pct,
            },
            _client_contact(client_id) or {},
            _store,
        )
    except Exception as e:
        # El ticket nunca puede tumbar una compra ya cobrada y acreditada.
        print(f"[arcadeStore] no se pudo emitir el ticket: {type(e).__name__}: {e}")


def _intent_dict(intent) -> dict:
    """
    Normaliza un PaymentIntent a dict plano.

    stripe 15.x devuelve StripeObject, que NO tiene `.get()` ni
    `.to_dict_recursive()`, y `dict(obj)` revienta con KeyError: 0 porque
    intenta indexar por entero. Lo unico fiable es `.to_dict()` — y hay que
    repetirlo en `metadata`, que sigue siendo StripeObject anidado.

    El webhook, en cambio, entrega el intent ya como dict de JSON.
    credit_stripe_chip_purchase recibe de ambos lados, asi que se normaliza
    aqui en vez de repartir `hasattr` por dentro.
    """
    if isinstance(intent, dict):
        data = dict(intent)
    elif hasattr(intent, "to_dict"):
        data = intent.to_dict()
    else:
        data = dict(intent)

    meta = data.get("metadata")
    if meta is not None and not isinstance(meta, dict):
        data["metadata"] = meta.to_dict() if hasattr(meta, "to_dict") else dict(meta)
    return data


def _pack_row(pack_key: str) -> dict:
    data = _exec_sp("sp_arcadeChipPacks_all", {"arcadeChipPacks": [{}]})
    for pack in data.get("arcadeChipPacks", []):
        if pack.get("packKey") == pack_key:
            return pack
    return {}


def arcade_checkout_sp(json_file: dict):
    """
    Abre el cobro con Stripe de un paquete de fichas (WEB).

    Devuelve el clientSecret para montar el Payment Element. El precio se lee
    del catalogo: el cliente elige QUE paquete, nunca CUANTO paga.
    """
    body = _first(json_file, "arcadePurchases")
    company_id = body.get("companyId")
    client_id = body.get("clientId")
    pack_key = body.get("packKey")

    if not (company_id and client_id and pack_key):
        return JSONResponse(
            content={"error": "missing_fields", "message": "Faltan datos de la compra"},
            status_code=400,
        )
    if not _stripe_ready():
        # Falla cerrado igual que IAP: sin pasarela no se regalan fichas.
        return JSONResponse(
            content={"error": "verification_unavailable",
                     "message": "El cobro con tarjeta no esta configurado"},
            status_code=503,
        )

    pack = _pack_row(pack_key)
    if not pack:
        return JSONResponse(
            content={"error": "unknown_pack", "message": "Ese paquete no existe"},
            status_code=400,
        )

    amount, chips, err = _pack_amount(pack, body.get("chips"))
    if err:
        return JSONResponse(content={
            "error": err,
            "message": "Cantidad de fichas fuera del rango permitido",
            "minChips": pack.get("minChips"), "maxChips": pack.get("maxChips"),
        }, status_code=400)
    if amount < 100:
        return JSONResponse(
            content={"error": "bad_amount", "message": "Monto minimo: $1.00 MXN"},
            status_code=400,
        )

    try:
        with timed_integration("stripe", "create_chip_intent") as span:
            intent = stripe.PaymentIntent.create(
                amount=amount,
                currency="mxn",
                description=f"Fichas de arcade: {pack['name']}",
                automatic_payment_methods={"enabled": True},
                metadata={
                    # El webhook y la confirmacion se apoyan en estos campos
                    # para saber que el cobro es de fichas y de quien.
                    "kind": ARCADE_INTENT_KIND,
                    "packKey": pack_key,
                    "clientId": str(client_id),
                    "companyId": str(company_id),
                    # Las fichas del monto libre viajan en la metadata para que
                    # el abono (y el webhook) sepan cuantas acreditar sin
                    # volver a confiar en el cliente.
                    "chips": str(chips),
                },
            )
            span.http_status = 200
    except Exception as e:
        log_workflow_step(
            "Chip Checkout Failed", workflow_name=WORKFLOW, action="web",
            status="FAILURE", entity="arcadePurchases", message=type(e).__name__,
        )
        return JSONResponse(content={"error": "stripe_error", "message": str(e)}, status_code=400)

    log_workflow_step(
        "Chip Checkout Opened", workflow_name=WORKFLOW, action="web",
        entity="arcadePurchases", message=f"{pack_key} — ${amount / 100:,.2f} MXN",
    )

    return JSONResponse(content={
        "clientSecret": intent["client_secret"],
        "paymentIntentId": intent["id"],
        "amount": amount,
        "currency": "mxn",
        "chips": chips,
    }, status_code=200)


def credit_stripe_chip_purchase(intent) -> dict:
    """
    Acredita las fichas de un PaymentIntent YA COBRADO.

    Lo llaman dos caminos: la confirmacion del navegador y el webhook de
    Stripe. Que ambos puedan llamarlo es a proposito — si el usuario cierra la
    pestana justo despues de pagar, el webhook termina el trabajo. El indice
    unico sobre (platform, storeTransactionId) hace que solo uno acredite.
    """
    intent = _intent_dict(intent)
    meta = intent.get("metadata") or {}
    pack_key = meta.get("packKey")
    client_id = meta.get("clientId")
    company_id = meta.get("companyId")

    if meta.get("kind") != ARCADE_INTENT_KIND or not (pack_key and client_id and company_id):
        return {"error": "not_a_chip_purchase"}
    if intent.get("status") != "succeeded":
        return {"error": "not_paid", "message": "El cobro no se completo"}

    amount = intent.get("amount_received") or intent.get("amount") or 0

    return _exec_sp("sp_arcadePurchases_credit", {"arcadePurchases": [{
        "companyId": int(company_id),
        "clientId": int(client_id),
        "packKey": pack_key,
        # Solo lo usa el paquete 'custom'; la SP revalida el rango igual.
        "chipsOverride": int(meta["chips"]) if str(meta.get("chips") or "").isdigit() else None,
        "platform": "web",
        "productId": f"stripe:{pack_key}",
        "storeTransactionId": intent["id"],
        "storeOriginalTransactionId": intent["id"],
        "priceCharged": round(amount / 100, 2),
        "currency": (intent.get("currency") or "mxn").upper(),
        "environment": _stripe_environment(),
    }]})


def arcade_confirm_sp(json_file: dict):
    """
    Confirma el cobro con Stripe y acredita las fichas.

    NO se confia en que el navegador diga "ya pague": se relee el
    PaymentIntent desde Stripe y solo se acredita si Stripe dice succeeded.
    """
    body = _first(json_file, "arcadePurchases")
    intent_id = body.get("paymentIntentId")
    client_id = body.get("clientId")

    if not (intent_id and client_id):
        return JSONResponse(
            content={"error": "missing_fields", "message": "Falta el identificador del cobro"},
            status_code=400,
        )
    if not _stripe_ready():
        return JSONResponse(
            content={"error": "verification_unavailable",
                     "message": "El cobro con tarjeta no esta configurado"},
            status_code=503,
        )

    try:
        with timed_integration("stripe", "retrieve_chip_intent") as span:
            # expand: sin el balance_transaction la comision seria la de la
            # formula, no la que Stripe cobro de verdad.
            intent = _intent_dict(stripe.PaymentIntent.retrieve(
                intent_id, expand=["latest_charge.balance_transaction"],
            ))
            span.http_status = 200
    except Exception as e:
        return JSONResponse(
            content={"error": "stripe_error", "message": str(e)}, status_code=502,
        )

    meta = intent.get("metadata") or {}
    # El intent tiene que ser de fichas Y de este cliente: sin esta comprobacion
    # bastaria conocer el id de un cobro ajeno para acreditarse sus fichas.
    if str(meta.get("clientId")) != str(client_id):
        return JSONResponse(
            content={"error": "not_your_purchase", "message": "Ese cobro no es tuyo"},
            status_code=403,
        )

    credited = credit_stripe_chip_purchase(intent)

    if "error" in credited:
        code = credited["error"]
        status = 402 if code in ("not_paid", "not_a_chip_purchase") else 500
        return JSONResponse(content=credited, status_code=status)

    if credited.get("status") == "already_credited":
        return JSONResponse(content={
            "status": "already_credited",
            "chipsCredited": 0,
            "coinBalance": credited.get("coinBalance"),
        }, status_code=200)

    log_workflow_step(
        "Chip Purchase Credited", workflow_name=WORKFLOW, action="web",
        entity="arcadePurchases", entity_id=credited.get("purchaseId"),
        message=f"{meta.get('packKey')} — {credited.get('chipsCredited')} fichas",
    )
    log_audit("arcadePurchases", credited.get("purchaseId"), "chipsCredited",
              None, credited.get("chipsCredited"), action="INSERT")

    _issue_ticket(credited, company_id=company_id, client_id=client_id,
                  pack=_pack_row(pack_key),
                  amount_cents=int(round((verified.get("priceCharged") or 0) * 100)),
                  currency=verified.get("currency") or "MXN",
                  reference=verified.get("storeTransactionId") or "")

    return JSONResponse(content={
        "status": "credited",
        "folio": credited.get("folio"),
        "chipsCredited": credited.get("chipsCredited"),
        "coinBalance": credited.get("coinBalance"),
    }, status_code=200)


# ---------------------------------------------------------------------------
# Compra en UN TOQUE con la tarjeta ya guardada
# ---------------------------------------------------------------------------
# El cliente ya tiene tarjeta en savedPaymentMethods (la misma que cobra las
# cuotas automaticas en modules/automatedPayments.py), asi que comprar fichas
# no tiene por que pedir los datos otra vez: se cobra off-session, igual que
# una cuota, y el dinero entra a la cuenta de SmartLoans.
#
# La CLABE no sirve para esto: SPEI lo empuja el usuario desde su banco y
# tarda: no hay forma de acreditar fichas en el momento. La tarjeta si.
#
# Si el banco pide 3-D Secure, el cobro off-session falla con
# authentication_required. Eso NO es un error a esconder: se devuelve tal cual
# para que la pantalla caiga al Payment Element y el usuario autentique. Sin
# ese respaldo, las tarjetas mexicanas —que piden 3DS muy seguido— quedarian
# sin poder comprar.
# ---------------------------------------------------------------------------

def arcade_quick_buy_sp(json_file: dict):
    """
    Cobra un paquete de fichas a la tarjeta guardada del cliente y acredita.

    Devuelve `no_saved_card` o `authentication_required` cuando hace falta
    pasar por el flujo con Payment Element; ninguno de los dos es una falla
    del sistema, son caminos previstos.
    """
    body = _first(json_file, "arcadePurchases")
    company_id = body.get("companyId")
    client_id = body.get("clientId")
    pack_key = body.get("packKey")

    if not (company_id and client_id and pack_key):
        return JSONResponse(
            content={"error": "missing_fields", "message": "Faltan datos de la compra"},
            status_code=400,
        )
    if not _stripe_ready():
        return JSONResponse(
            content={"error": "verification_unavailable",
                     "message": "El cobro con tarjeta no esta configurado"},
            status_code=503,
        )

    pack = _pack_row(pack_key)
    if not pack:
        return JSONResponse(
            content={"error": "unknown_pack", "message": "Ese paquete no existe"},
            status_code=400,
        )

    # Import perezoso: automatedPayments importa de stripe_payments y un import
    # a nivel de modulo arriesga un ciclo (mismo patron que el resto del repo).
    from modules.automatedPayments import _sp_saved_methods

    pm_data = _sp_saved_methods({
        "action": "get", "clientId": client_id, "companyId": company_id,
    })
    pm_id = (pm_data or {}).get("stripePaymentMethodId")

    if not pm_id:
        return JSONResponse(content={
            "error": "no_saved_card",
            "message": "No tienes una tarjeta guardada",
        }, status_code=409)

    amount, chips, err = _pack_amount(pack, body.get("chips"))
    if err:
        return JSONResponse(content={
            "error": err,
            "message": "Cantidad de fichas fuera del rango permitido",
            "minChips": pack.get("minChips"), "maxChips": pack.get("maxChips"),
        }, status_code=400)

    try:
        with timed_integration("stripe", "chip_offsession_charge") as span:
            intent = stripe.PaymentIntent.create(
                amount=amount,
                currency="mxn",
                payment_method=pm_id,
                confirm=True,
                off_session=True,
                description=f"Fichas de arcade: {pack['name']}",
                metadata={
                    "kind": ARCADE_INTENT_KIND,
                    "packKey": pack_key,
                    "clientId": str(client_id),
                    "companyId": str(company_id),
                    "chips": str(chips),
                },
            )
            intent = _intent_dict(intent)
            span.http_status = 200
    except stripe.error.CardError as e:
        err = e.error
        code = getattr(err, "code", "card_declined")
        # 3DS: el intent ya existe, asi que la pantalla puede retomarlo con el
        # Payment Element en vez de empezar el cobro de cero.
        if code == "authentication_required":
            payment_intent = getattr(err, "payment_intent", None) or {}
            return JSONResponse(content={
                "error": "authentication_required",
                "message": "Tu banco pide confirmar la compra",
                "clientSecret": payment_intent.get("client_secret"),
                "paymentIntentId": payment_intent.get("id"),
            }, status_code=409)
        log_workflow_step(
            "Chip Quick Buy Declined", workflow_name=WORKFLOW, action="saved_card",
            status="FAILURE", entity="arcadePurchases", message=f"{pack_key} — {code}",
        )
        return JSONResponse(content={
            "error": "card_declined",
            "message": getattr(err, "message", "Tu tarjeta fue rechazada"),
        }, status_code=402)
    except Exception as e:
        return JSONResponse(content={"error": "stripe_error", "message": str(e)}, status_code=502)

    if intent.get("status") != "succeeded":
        # Cualquier otro estado (processing, requires_action) deja el cobro
        # abierto: no se acredita nada y el webhook cerrara si prospera.
        return JSONResponse(content={
            "error": "not_paid",
            "message": "El cobro no se completo",
            "paymentIntentId": intent["id"],
            "status": intent.get("status"),
        }, status_code=402)

    credited = credit_stripe_chip_purchase(intent)
    if "error" in credited:
        return JSONResponse(content=credited, status_code=500)

    if credited.get("status") == "already_credited":
        return JSONResponse(content={
            "status": "already_credited", "chipsCredited": 0,
            "coinBalance": credited.get("coinBalance"),
        }, status_code=200)

    log_workflow_step(
        "Chip Purchase Credited", workflow_name=WORKFLOW, action="saved_card",
        entity="arcadePurchases", entity_id=credited.get("purchaseId"),
        message=f"{pack_key} — {credited.get('chipsCredited')} fichas, ${amount / 100:,.2f} MXN",
    )
    log_audit("arcadePurchases", credited.get("purchaseId"), "chipsCredited",
              None, credited.get("chipsCredited"), action="INSERT")

    fee, net, pct = _stripe_fee(
        stripe.PaymentIntent.retrieve(intent["id"], expand=["latest_charge.balance_transaction"]),
        amount / 100.0,
    )
    _issue_ticket(credited, company_id=company_id, client_id=client_id, pack=pack,
                  amount_cents=amount, currency="MXN", reference=intent["id"],
                  fee=fee, net=net, fee_pct=pct)

    return JSONResponse(content={
        "status": "credited",
        "folio": credited.get("folio"),
        "chipsCredited": credited.get("chipsCredited"),
        "coinBalance": credited.get("coinBalance"),
        "card": {"brand": pm_data.get("brand"), "last4": pm_data.get("last4")},
    }, status_code=200)


def arcade_saved_card_sp(json_file: dict):
    """Tarjeta guardada del cliente, para pintar 'Pagar con •••• 4242'."""
    body = _first(json_file, "arcadePurchases")
    try:
        from modules.automatedPayments import _sp_saved_methods
        pm = _sp_saved_methods({
            "action": "get",
            "clientId": body.get("clientId"),
            "companyId": body.get("companyId"),
        }) or {}
        if not pm.get("stripePaymentMethodId"):
            return JSONResponse(content={"card": None}, status_code=200)
        # Nunca sale el id del metodo de pago al cliente: solo lo pintable.
        return JSONResponse(content={"card": {
            "brand": pm.get("brand"), "last4": pm.get("last4"),
            "expiryMonth": pm.get("expiryMonth"), "expiryYear": pm.get("expiryYear"),
        }}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"card": None, "error": str(e)}, status_code=200)


# ---------------------------------------------------------------------------
# SPEI — comprar fichas por transferencia
# ---------------------------------------------------------------------------
# SPEI NO SE COBRA, SE RECIBE: el usuario empuja la transferencia desde su
# banco y nosotros solo podemos detectarla. De ahi el flujo orden -> declarar
# -> conciliar, y que las fichas se acrediten SOLO al conciliar.
#
# QUIEN PAGA NO CONFIRMA. Si bastara con que el cliente dijera "ya transferi",
# cualquiera se regalaria fichas inventando una clave de rastreo. Confirma la
# conciliacion bancaria o un administrador contra el estado de cuenta.
#
# La CLABE de destino vive en configuracion. Deberia mudarse a ajustes por
# compania cuando exista esa tabla: bankAccounts es por CLIENTE (clientId NOT
# NULL) y no tiene donde guardar la cuenta receptora del negocio.
# ---------------------------------------------------------------------------

def _spei_destination() -> dict:
    return {
        "clabe": os.getenv("ARCADE_SPEI_CLABE", ""),
        "bankName": os.getenv("ARCADE_SPEI_BANK", ""),
        "beneficiary": os.getenv("ARCADE_SPEI_BENEFICIARY", ""),
    }


def arcade_spei_order_sp(json_file: dict):
    """
    Abre una orden de compra por SPEI y devuelve los datos de la transferencia.

    NO acredita fichas: solo aparta la intencion con una referencia unica que
    el usuario debe escribir en el concepto para poder casar el deposito.
    """
    body = _first(json_file, "arcadeChipOrders")
    company_id = body.get("companyId")
    client_id = body.get("clientId")
    pack_key = body.get("packKey")

    if not (company_id and client_id and pack_key):
        return JSONResponse(
            content={"error": "missing_fields", "message": "Faltan datos de la compra"},
            status_code=400,
        )

    destination = _spei_destination()
    if not destination["clabe"]:
        # Falla cerrado: sin CLABE de destino no hay adonde transferir y una
        # orden sin cuenta solo generaria depositos perdidos.
        return JSONResponse(
            content={"error": "spei_unavailable",
                     "message": "El pago por transferencia no esta configurado"},
            status_code=503,
        )

    pack = _pack_row(pack_key)
    if not pack:
        return JSONResponse(
            content={"error": "unknown_pack", "message": "Ese paquete no existe"},
            status_code=400,
        )

    amount_cents, chips, err = _pack_amount(pack, body.get("chips"))
    if err:
        return JSONResponse(content={
            "error": err, "message": "Cantidad de fichas fuera del rango permitido",
            "minChips": pack.get("minChips"), "maxChips": pack.get("maxChips"),
        }, status_code=400)

    # Referencia corta y aleatoria: entra en el concepto de SPEI y no se puede
    # adivinar la de otro cliente.
    reference = f"ARC{secrets.token_hex(4).upper()}"

    try:
        created = _exec_sp("sp_arcadeChipOrders_create", {"arcadeChipOrders": [{
            "companyId": company_id, "clientId": client_id, "packKey": pack_key,
            "chips": chips, "amountMXN": round(amount_cents / 100, 2),
            "reference": reference, "expiresInHours": 48,
        }]})
    except Exception as e:
        # Sin este guardia un error de base salia como traceback sin manejar.
        print(f"[arcadeStore] no se pudo abrir la orden SPEI: {type(e).__name__}: {e}")
        return JSONResponse(
            content={"error": "order_failed", "message": "No se pudo abrir la orden"},
            status_code=500,
        )
    if "error" in created:
        return JSONResponse(content=created, status_code=400)

    log_workflow_step(
        "Chip SPEI Order Opened", workflow_name=WORKFLOW, action="spei",
        entity="arcadeChipOrders", entity_id=created.get("orderId"),
        message=f"{pack_key} — ${amount_cents / 100:,.2f} MXN ref {reference}",
    )

    return JSONResponse(content={**created, "destination": destination}, status_code=200)


def arcade_spei_declare_sp(json_file: dict):
    """
    El cliente declara su clave de rastreo.

    Deja constancia y NADA MAS: lo que afirma quien paga no acredita fichas.
    """
    try:
        data = _exec_sp("sp_arcadeChipOrders_declare", json_file)
        code = data.get("error")
        if code:
            status = 409 if code in ("clave_already_used", "order_not_open") else 400
            return JSONResponse(content=data, status_code=status)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def arcade_spei_confirm_sp(json_file: dict):
    """
    Concilia la orden y acredita las fichas.

    SOLO para conciliacion/administracion — la ruta lo advierte y la puerta de
    rol va en la capa de arriba. Es idempotente: reconfirmar no vuelve a
    acreditar.
    """
    try:
        data = _exec_sp("sp_arcadeChipOrders_confirm", json_file)
        code = data.get("error")
        if code:
            status = 409 if code == "amount_mismatch" else 400 if code in (
                "order_not_found", "no_clave") else 500
            return JSONResponse(content=data, status_code=status)

        if data.get("status") == "credited":
            log_workflow_step(
                "Chip SPEI Confirmed", workflow_name=WORKFLOW, action="spei",
                entity="arcadeChipOrders", entity_id=data.get("orderId"),
                message=f"{data.get('chipsCredited')} fichas — folio {data.get('folio')}",
            )
            log_audit("arcadeChipOrders", data.get("orderId"), "status",
                      "declared", "confirmed", action="CONFIRM")
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def arcade_spei_orders_all_sp(json_file: dict):
    """Ordenes del cliente, o bandeja de conciliacion filtrando por status."""
    try:
        data = _exec_sp("sp_arcadeChipOrders_all", json_file)
        if "error" in data:
            return JSONResponse(content=data, status_code=500)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
