"""
Accounts that receive money for a company (architecture D1, RFC-010). Top-ups are
charged on the company's own Stripe account, and transfers go to its CLABE, so what
is stored here decides where customers' money lands: nothing writes it from a
public route, and a second admin must confirm it.
"""
import hashlib
import json
from fastapi.responses import JSONResponse
from databases import connection
from modules.bankAccounts import BANK_CODES, validate_clabe
from observability.logger import log_audit

WALLET_TOPUP_PURPOSE = "wallet_topup"

# RFC-010 Amendment A: companies the platform owns may charge card top-ups on the
# platform's own Stripe account. Any other company needs its own (stripe_connect),
# so a third party's money never lands in ours. Lavandería = 1.
PLATFORM_TOPUP_COMPANIES = frozenset({1})
# Stands for "charge on the platform account": never a real Stripe id, never sent to the app.
PLATFORM_ACCOUNT = "platform"
_ACTION_INSERT, _ACTION_UPDATE, _ACTION_CONFIRM = 1, 2, 4


def _read(procedure: str, row: dict) -> list:
    """Rows of a read SP (FOR JSON, ROOT companyPaymentAccounts)."""
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{procedure}] @pjsonfile = %s",
                       (json.dumps({"companyPaymentAccounts": [row]}),))
        raw = "".join(r[0] for r in cursor.fetchall() if r and r[0])
        return json.loads(raw).get("companyPaymentAccounts", []) if raw else []
    finally:
        if conn:
            conn.close()


def _write(row: dict) -> dict:
    """{ value, msg, error } from sp_companyPaymentAccounts; error "1" means refused."""
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_companyPaymentAccounts] @pjsonfile = %s",
                       (json.dumps({"companyPaymentAccounts": [row]}),))
        value, msg, error = cursor.fetchone()
        return {"value": value, "msg": msg, "error": error}
    finally:
        if conn:
            conn.close()


def _failed(result: dict) -> bool:
    return str(result.get("error") or "") == "1"


def _active_rows(json_file: dict) -> list:
    """ACTIVE rows, or [] on any failure: that keeps top-ups off rather than
    falling back to the platform account."""
    try:
        return _read("sp_companyPaymentAccounts_active", {
            "companyId": json_file.get("companyId"),
            "purpose": json_file.get("purpose") or WALLET_TOPUP_PURPOSE,
        })
    except Exception as e:
        print(f"[companyPaymentAccounts] active lookup failed: {e}")
        return []


def platform_allowed(company_id: object) -> bool:
    try:
        return int(company_id) in PLATFORM_TOPUP_COMPANIES
    except (TypeError, ValueError):
        return False


def _stripe_id(rows: list, company_id: object) -> str:
    """The company's own Stripe account, PLATFORM_ACCOUNT, or "" (top-ups off)."""
    own = next((str(r["stripeConnectedAccountId"]) for r in rows
                if r.get("accountType") == "stripe_connect" and r.get("chargesEnabled")), "")
    if own:
        return own
    if platform_allowed(company_id) and any(r.get("accountType") == "stripe_platform" for r in rows):
        return PLATFORM_ACCOUNT
    return ""


def active_stripe_account(json_file: dict) -> str:
    """The account a company's card top-ups are charged on, or "" when they're off."""
    return _stripe_id(_active_rows(json_file), json_file.get("companyId"))


def active_accounts(json_file: dict) -> JSONResponse:
    """POST /companyPaymentAccounts/active: what a customer may see. Only a
    confirmed CLABE, and never the Stripe account id."""
    rows = _active_rows(json_file)
    spei = next((r for r in rows if r.get("accountType") == "spei"), None)
    return JSONResponse({
        "cardTopUpAvailable": bool(_stripe_id(rows, json_file.get("companyId"))),
        "transferAccount": spei and {k: spei.get(k) for k in ("holderName", "clabe", "bankName", "terminalName")},
    }, status_code=200)


def list_accounts(json_file: dict) -> list:
    return _read("sp_companyPaymentAccounts_all", {"companyId": json_file.get("companyId")})


def add_stripe_account(json_file: dict) -> dict:
    result = _write({"action": _ACTION_INSERT, "accountType": "stripe_connect", **json_file})
    if _failed(result):
        return {"error": result.get("msg")}
    log_audit("CompanyPaymentAccount", int(result["value"]), "stripeConnectedAccountId",
              None, json_file.get("stripeConnectedAccountId"), action="INSERT")
    return {"companyPaymentAccountId": int(result["value"])}


def add_platform_account(json_file: dict) -> JSONResponse:
    """An admin asks to charge top-ups on the platform's Stripe account. Only a
    company the platform owns may, and a second admin must still confirm it."""
    row = (json_file.get("companyPaymentAccounts") or [{}])[0]
    company_id = row.get("companyId")
    if not platform_allowed(company_id):
        return JSONResponse({"error": "platform_not_allowed"}, status_code=400)
    try:
        if any(a.get("accountType") == "stripe_platform" and a.get("accountStatus") != "ARCHIVED"
               for a in list_accounts({"companyId": company_id})):
            return JSONResponse({"error": "platform_already_requested"}, status_code=400)
        result = _write({
            "action": _ACTION_INSERT, "accountType": "stripe_platform", "companyId": company_id,
            "purpose": WALLET_TOPUP_PURPOSE, "holderName": str(row.get("holderName") or "Cuenta Stripe de GMO"),
            "createdByUserId": row.get("createdByUserId"),
        })
        if _failed(result):
            return JSONResponse({"error": result.get("msg")}, status_code=400)
        log_audit("CompanyPaymentAccount", int(result["value"]), "accountType", None, "stripe_platform",
                  action="INSERT")
        return JSONResponse({"result": [result]}, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def sync_charges_enabled(json_file: dict) -> None:
    acct_id = json_file.get("stripeConnectedAccountId")
    enabled = 1 if json_file.get("chargesEnabled") else 0
    result = _write({"action": _ACTION_UPDATE, "stripeConnectedAccountId": acct_id, "chargesEnabled": enabled})
    if str(result.get("value") or "0") != "0":
        log_audit("CompanyPaymentAccount", None, f"chargesEnabled:{acct_id}", None, enabled, action="UPDATE")


def add_transfer_account(json_file: dict) -> JSONResponse:
    """An admin registers the CLABE; it stays hidden from customers until a second
    admin confirms it, because changing it is how money gets diverted."""
    row = (json_file.get("companyPaymentAccounts") or [{}])[0]
    clabe = str(row.get("clabe") or "").strip()
    holder = str(row.get("holderName") or "").strip()
    valid, problem = validate_clabe(clabe)
    if not valid:
        return JSONResponse({"error": problem}, status_code=400)
    if not holder:
        return JSONResponse({"error": "El titular es obligatorio."}, status_code=400)
    if not row.get("commissionTerminalId"):
        return JSONResponse({"error": "La cuenta debe tener una terminal asignada."}, status_code=400)
    try:
        result = _write({
            "action": _ACTION_INSERT, "accountType": "spei", "companyId": row.get("companyId"),
            "purpose": WALLET_TOPUP_PURPOSE, "clabe": clabe,
            "clabeHash": hashlib.sha256(clabe.encode()).hexdigest(), "holderName": holder,
            "bankName": BANK_CODES.get(clabe[:3], ""), "createdByUserId": row.get("createdByUserId"),
            "commissionTerminalId": row.get("commissionTerminalId"),
        })
        if _failed(result):
            return JSONResponse({"error": result.get("msg")}, status_code=400)
        log_audit("CompanyPaymentAccount", int(result["value"]), "clabeLast4", None, clabe[-4:], action="INSERT")
        return JSONResponse({"result": [result]}, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def confirm_account(json_file: dict) -> JSONResponse:
    """A second admin activates a pending account; the SP archives the previous one."""
    result = _write({"action": _ACTION_CONFIRM, "companyPaymentAccountId": json_file.get("companyPaymentAccountId"),
                     "companyId": json_file.get("companyId"), "verifiedByUserId": json_file.get("verifiedByUserId")})
    if _failed(result):
        return JSONResponse({"error": result.get("msg")}, status_code=400)
    log_audit("CompanyPaymentAccount", json_file.get("companyPaymentAccountId"), "accountStatus",
              "PENDING_VERIFICATION", "ACTIVE", action="UPDATE")
    return JSONResponse({"result": [result]}, status_code=200)
