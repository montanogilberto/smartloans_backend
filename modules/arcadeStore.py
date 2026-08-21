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
                span["statusCode"] = res.status_code
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
            span["statusCode"] = res.status_code
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
            span["statusCode"] = res.status_code

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
    if platform not in ("ios", "android"):
        return JSONResponse(
            content={"error": "bad_platform", "message": "Plataforma no soportada"},
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

    return JSONResponse(content={
        "status": "credited",
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
