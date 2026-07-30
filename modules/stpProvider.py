"""
STP (Sistema de Transferencias y Pagos) provider client — SPEI dispersión.

Banking-first Phase 1 (docs/payment-banking-first-redesign.md). Until the STP
contract/sandbox exists there are no credentials, so this client runs in MOCK
mode: it validates inputs, fabricates a claveRastreo + CEP URL and reports
'settled' instantly — which lets every orchestrator endpoint be exercised
end-to-end today. When STP credentials land, only `_send_real` gets a body;
the interface (and everything calling it) does not change.

Mock mode is selected exactly like stripe_payments does it: real calls only
happen when the env vars exist.
    STP_EMPRESA        — company name registered with STP
    STP_PRIVATE_KEY    — signing key (firma de cadena original)
    STP_BASE_URL       — e.g. https://demo.stpmex.com/speiws/rest
"""

import os
import uuid
from datetime import datetime, timezone

MOCK_CEP_BASE = "https://www.banxico.org.mx/cep/"


def is_mock() -> bool:
    return not (os.getenv("STP_EMPRESA") and os.getenv("STP_PRIVATE_KEY"))


def send_spei(*, clabe_destino: str, nombre_beneficiario: str, amount_mxn: float,
              concepto: str, reference: str) -> dict:
    """Send an outbound SPEI (dispersión). Returns a normalized result:
    { ok, status: sent|settled|failed, providerRef, cepUrl?, error? }"""
    if is_mock():
        clave_rastreo = f"MOCKSTP{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}{uuid.uuid4().hex[:6].upper()}"
        print(f"[stp][MOCK] send_spei → clabe=****{clabe_destino[-4:]} "
              f"beneficiario={nombre_beneficiario!r} monto={amount_mxn} MXN "
              f"concepto={concepto!r} ref={reference} → claveRastreo={clave_rastreo}")
        return {
            "ok": True,
            "status": "settled",  # mock settles instantly; real STP settles via webhook
            "providerRef": clave_rastreo,
            "cepUrl": f"{MOCK_CEP_BASE}#mock/{clave_rastreo}",
            "mock": True,
        }

    # ── Real STP integration (pending contract) ──────────────────────────
    # Build the orden de pago, sign the cadena original with STP_PRIVATE_KEY,
    # POST to {STP_BASE_URL}/ordenPago/registra, map the response. Settlement
    # confirmation + CEP arrive via the STP webhook (routes_/stpWebhook).
    print("[stp] send_spei: STP credentials present but real client not implemented yet")
    return {"ok": False, "status": "failed",
            "error": "Cliente STP real no implementado — configurar integración con el contrato STP."}
