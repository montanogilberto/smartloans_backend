"""
Bank accounts (CLABE) — link + verify + CRUD. Banking-first Phase 1.

Spec: posgmo-factory/tests/prd_bankAccount.json and
docs/payment-banking-first-redesign.md §9 (/bank-account/link, /bank-account/verify).

The CLABE is personal financial data (LFPDPPP): modules only ever log/return
the last 4 digits; the full number lives in SQL and is read back solely by the
orchestrator to address SPEI transfers.
"""

import json
import os
import secrets
from fastapi.responses import JSONResponse
from databases import connection

from modules.stpProvider import is_mock


# RFC-018 §3.3: wrong micro-deposit guesses allowed before the account locks.
MAX_VERIFICATION_ATTEMPTS = int(os.getenv("MICRODEPOSIT_MAX_ATTEMPTS", "3"))

# Fields the public /bankAccounts passthrough may never set.
_VERIFICATION_FIELDS = {"isVerified", "verificationCents", "verificationAttempts", "verifiedAt"}


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
        # Idempotent re-link: the same client re-submitting the same CLABE gets
        # their existing account back (with its pending verification state if
        # any) instead of a raw UNIQUE-index error.
        if "duplicate" in result["error"].lower():
            existing = _sp("sp_bankAccounts_all", {"bankAccounts": [{
                "companyId": company_id, "clientId": client_id,
            }]}).get("bankAccounts", [])
            match = next((a for a in existing if a.get("clabeLast4") == clabe[-4:]
                          and a.get("bankCode") == bank_code), None)
            if match:
                print(f"[bankAccounts] link REPLAY clientId={client_id} → bankAccountId={match['bankAccountId']} "
                      f"(verified={match.get('isVerified')})")
                body = {**match, "alreadyLinked": True,
                        "status": "verified" if match.get("isVerified") else "pending_verification"}
                if not match.get("isVerified") and is_mock():
                    full = _sp("sp_bankAccounts_one", {"bankAccounts": [{"bankAccountId": match["bankAccountId"]}]})
                    if full.get("verificationCents"):
                        body["mockVerificationCents"] = full["verificationCents"]
                return JSONResponse(body, status_code=200)
        return JSONResponse(result, status_code=400)

    # Real mode: send the actual micro-deposit via SPEI here (1–99 centavos to
    # the CLABE) so the client can read it off their statement. NOT implemented
    # yet (and needs an RFC — SmartLoans is non-custodial), so report
    # microDepositSent=False instead of letting the UI claim it was sent.
    body = {**result, "status": "pending_verification", "verificationMethod": "micro_deposit",
            "microDepositSent": False}
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
    try:
        amount_cents = int(amount_cents)
    except (TypeError, ValueError):
        amount_cents = 0
    if not 1 <= amount_cents <= 99:
        # Malformed input never costs an attempt.
        return JSONResponse({"verified": False, "error": "Ingresa los centavos recibidos (1–99)."}, status_code=400)

    row = _sp("sp_bankAccounts_one", {"bankAccounts": [{"bankAccountId": bank_account_id}]})
    if not row or row.get("clientId") != client_id:
        return JSONResponse({"error": "Cuenta bancaria no encontrada."}, status_code=404)
    if row.get("isVerified"):
        return JSONResponse({"verified": True, "message": "La cuenta ya estaba verificada."}, status_code=200)

    # RFC-018 §3.3: the SP compares and counts in one transaction. Fail closed:
    # if the SP can't count (migration / SP not deployed yet) nobody verifies.
    attempt = _sp("sp_bankAccounts", {"bankAccounts": [{
        "action": 4, "bankAccountId": bank_account_id, "clientId": client_id,
        "amountCents": amount_cents, "maxAttempts": MAX_VERIFICATION_ATTEMPTS,
    }]})
    if not isinstance(attempt, dict) or "matched" not in attempt:
        print(f"[bankAccounts] verify UNAVAILABLE bankAccountId={bank_account_id} "
              f"(attempt counter missing: {attempt.get('error') if isinstance(attempt, dict) else type(attempt).__name__})")
        return JSONResponse({"verified": False,
                             "error": "No pudimos verificar tu cuenta en este momento. Intenta más tarde."},
                            status_code=503)
    remaining = attempt.get("attemptsRemaining", 0)
    if not attempt.get("matched"):
        if attempt.get("locked"):
            print(f"[bankAccounts] verify LOCKED bankAccountId={bank_account_id} attempts={attempt.get('attempts')}")
            return JSONResponse({"verified": False, "locked": True, "attemptsRemaining": 0,
                                 "error": "Demasiados intentos. Contacta a soporte para desbloquear la verificación."},
                                status_code=423)
        print(f"[bankAccounts] verify FAILED bankAccountId={bank_account_id} (centavos no coinciden, quedan {remaining})")
        plural = "intento" if remaining == 1 else "intentos"
        return JSONResponse({"verified": False, "locked": False, "attemptsRemaining": remaining,
                             "error": f"El monto no coincide. Te quedan {remaining} {plural}."},
                            status_code=400)

    result = _sp("sp_bankAccounts", {"bankAccounts": [{
        "action": 2, "bankAccountId": bank_account_id, "companyId": company_id,
        "isVerified": True,
    }]})
    print(f"[bankAccounts] VERIFIED bankAccountId={bank_account_id} clientId={client_id}")
    return JSONResponse({"verified": True, **result}, status_code=200)


def bank_accounts_sp(json_file: dict):
    """CRUD passthrough (sp_bankAccounts). Prefer /bank-account/link for creates —
    it validates the CLABE and starts verification."""
    # Verification state only changes through /bank-account/verify (attempt
    # limit, RFC-018 §3.3). This route has no auth, so letting it set
    # isVerified / the code / the counter would bypass verification entirely.
    for req in (json_file.get("bankAccounts") or []):
        if not isinstance(req, dict):
            continue
        blocked = _VERIFICATION_FIELDS.intersection(req)
        if blocked or str(req.get("action")) == "4":
            print(f"[bankAccounts] passthrough REJECTED verification fields={sorted(blocked)} action={req.get('action')}")
            return JSONResponse({"error": "La verificación de la cuenta sólo se hace con /bank-account/verify."},
                                status_code=403)
    try:
        return JSONResponse(_sp("sp_bankAccounts", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def _annotate_verification(account: dict) -> dict:
    """Tell the UI the truth about an unverified account's micro-deposit.

    No real SPEI micro-deposit is sent yet (stpProvider has no real client), so
    `microDepositSent` is always False. In MOCK mode the pending code is attached
    as `mockVerificationCents` so the test flow survives a reload — never in
    real mode."""
    if account.get("isVerified"):
        return account
    account["microDepositSent"] = False
    attempts = account.get("verificationAttempts")
    if isinstance(attempts, int):  # absent until the migration has run
        account["attemptsRemaining"] = max(MAX_VERIFICATION_ATTEMPTS - attempts, 0)
        account["verificationLocked"] = attempts >= MAX_VERIFICATION_ATTEMPTS
    if is_mock() and account.get("bankAccountId") and not account.get("verificationLocked"):
        full = _sp("sp_bankAccounts_one", {"bankAccounts": [{"bankAccountId": account["bankAccountId"]}]})
        if full.get("verificationCents"):
            account["mockVerificationCents"] = full["verificationCents"]
    return account


def all_bank_accounts_sp(json_file: dict):
    try:
        result = _sp("sp_bankAccounts_all", json_file)
        accounts = result.get("bankAccounts") if isinstance(result, dict) else None
        if isinstance(accounts, list):
            result["bankAccounts"] = [_annotate_verification(a) for a in accounts]
        return JSONResponse(result, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def bank_accounts_lifecycle_sp(json_file: dict):
    """add_pending | promote_primary | archive | snapshot_for_loan |
    reveal_counterparty | check_duplicate via sp_bankAccountsLifecycle
    (RFC-001, sql/sp_bankAccountsLifecycle.sql). Was defined in SQL since
    RFC-001 landed but never had a Python/route wiring until RFC-002 Phase 1
    needed snapshot_for_loan for paymentIntents.create's beneficiarySnapshotId."""
    req = (json_file.get("bankAccounts") or [{}])[0]
    if req.get("action") == "reveal_counterparty":
        # RFC-016 fase 3b: no counterparty CLABE (so no SPEI) until the loan's
        # platform fee is PAID.
        from modules.platformFees import require_fee_paid
        blocked = require_fee_paid(req.get("companyId"), req.get("loanId"))
        if blocked:
            return JSONResponse({"error": blocked, "code": "PLATFORM_FEE_UNPAID"}, status_code=409)
    try:
        return JSONResponse(_sp("sp_bankAccountsLifecycle", json_file), status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
