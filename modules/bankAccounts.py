"""
Bank accounts (CLABE) — link + verify + CRUD. Banking-first Phase 1.

Spec: posgmo-factory/tests/prd_bankAccount.json and
docs/payment-banking-first-redesign.md §9 (/bank-account/link, /bank-account/verify).

The CLABE is personal financial data (LFPDPPP): modules only ever log/return
the last 4 digits; the full number lives in SQL and is read back solely by the
orchestrator to address SPEI transfers.
"""

import json
import secrets
from fastapi.responses import JSONResponse
from databases import connection

from modules.stpProvider import is_mock


def _conn():
    return connection()


def _sp(proc: str, json_file: dict):
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{proc}] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


# ── CLABE validation ────────────────────────────────────────────────────────

# ABM bank codes — the common ones; unknown prefixes still link, just without
# a resolved bank name.
BANK_CODES = {
    "002": "Banamex (Citibanamex)", "012": "BBVA México", "014": "Santander México",
    "021": "HSBC México", "030": "Banco del Bajío", "036": "Inbursa",
    "044": "Scotiabank", "058": "Banregio", "059": "Invex", "072": "Banorte",
    "106": "Bank of America México", "127": "Banco Azteca", "137": "BanCoppel",
    "646": "STP", "684": "Transfer (OPM)", "722": "Mercado Pago (NVIO)",
    "710": "NU México", "661": "Klar (Alternativos)", "638": "Nu/Akala",
}

_CLABE_WEIGHTS = [3, 7, 1] * 6  # 18 positions; checksum uses the first 17


def validate_clabe(clabe: str) -> tuple[bool, str]:
    """Standard CLABE check-digit validation (mod-10 over weights 3,7,1)."""
    clabe = (clabe or "").strip()
    if not clabe.isdigit() or len(clabe) != 18:
        return False, "La CLABE debe tener exactamente 18 dígitos."
    total = sum((int(d) * w) % 10 for d, w in zip(clabe[:17], _CLABE_WEIGHTS))
    control = (10 - (total % 10)) % 10
    if control != int(clabe[17]):
        return False, "CLABE inválida (dígito de control no coincide)."
    return True, ""


# ── Endpoints ───────────────────────────────────────────────────────────────

async def link_bank_account(payload: dict):
    """POST /bank-account/link — validate the CLABE, resolve the bank, create the
    row with a pending micro-deposit code. In mock mode the code is returned in
    the response (there is no real deposit to check the statement for)."""
    client_id   = payload.get("clientId")
    company_id  = payload.get("companyId")
    clabe       = (payload.get("clabe") or "").strip()
    holder_name = (payload.get("holderName") or "").strip()

    if not client_id or not company_id or not holder_name:
        return JSONResponse({"error": "clientId, companyId y holderName son requeridos"}, status_code=400)

    ok, err = validate_clabe(clabe)
    if not ok:
        print(f"[bankAccounts] link REJECTED clientId={client_id}: {err}")
        return JSONResponse({"error": err}, status_code=400)

    bank_code = clabe[:3]
    bank_name = BANK_CODES.get(bank_code, f"Banco {bank_code}")
    verification_cents = secrets.randbelow(98) + 1  # 1–99 centavos

    print(f"[bankAccounts] link clientId={client_id} clabe=****{clabe[-4:]} bank={bank_name}")
    result = _sp("sp_bankAccounts", {"bankAccounts": [{
        "action": 1, "companyId": company_id, "clientId": client_id,
        "clabe": clabe, "bankCode": bank_code, "bankName": bank_name,
        "holderName": holder_name, "verificationMethod": "micro_deposit",
        "verificationCents": verification_cents,
    }]})
    if result.get("error"):
        return JSONResponse(result, status_code=400)

    # Real mode: send the actual micro-deposit via SPEI here (1–99 centavos to
    # the CLABE) so the client can read it off their statement.
    body = {**result, "status": "pending_verification", "verificationMethod": "micro_deposit"}
    if is_mock():
        # No real deposit exists to look up — surface the code so the flow is
        # testable end-to-end. Never present in real mode.
        body["mockVerificationCents"] = verification_cents
        print(f"[bankAccounts][MOCK] micro-deposit code for testing: {verification_cents} centavos")
    return JSONResponse(body, status_code=200)


async def verify_bank_account(payload: dict):
    """POST /bank-account/verify — client enters the centavos they received;
    on match the account is marked verified (and default if it's their first)."""
    client_id       = payload.get("clientId")
    company_id      = payload.get("companyId")
    bank_account_id = payload.get("bankAccountId")
    amount_cents    = payload.get("amountCents")

    if not bank_account_id or amount_cents is None:
        return JSONResponse({"error": "bankAccountId y amountCents son requeridos"}, status_code=400)

    row = _sp("sp_bankAccounts_one", {"bankAccounts": [{"bankAccountId": bank_account_id}]})
    if not row or row.get("clientId") != client_id:
        return JSONResponse({"error": "Cuenta bancaria no encontrada."}, status_code=404)
    if row.get("isVerified"):
        return JSONResponse({"verified": True, "message": "La cuenta ya estaba verificada."}, status_code=200)
    if int(amount_cents) != int(row.get("verificationCents") or -1):
        print(f"[bankAccounts] verify FAILED bankAccountId={bank_account_id} (centavos no coinciden)")
        return JSONResponse({"verified": False, "error": "El monto no coincide. Revisa tu estado de cuenta."}, status_code=400)

    result = _sp("sp_bankAccounts", {"bankAccounts": [{
        "action": 2, "bankAccountId": bank_account_id, "companyId": company_id,
        "isVerified": True,
    }]})
    print(f"[bankAccounts] VERIFIED bankAccountId={bank_account_id} clientId={client_id}")
    return JSONResponse({"verified": True, **result}, status_code=200)


def bank_accounts_sp(json_file: dict):
    """CRUD passthrough (sp_bankAccounts). Prefer /bank-account/link for creates —
    it validates the CLABE and starts verification."""
    try:
        return JSONResponse(_sp("sp_bankAccounts", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def all_bank_accounts_sp(json_file: dict):
    try:
        return JSONResponse(_sp("sp_bankAccounts_all", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
