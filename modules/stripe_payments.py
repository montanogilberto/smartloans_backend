"""
Stripe Connect — P2P Lending Payment Module

Money flow:
  1. Lender calls /stripe/connected-accounts → creates Express account → KYC via /stripe/onboarding-link
  2. Lender calls /stripe/wallet/top-up → PaymentIntent charges lender's card →
     funds held in platform Stripe account tagged to lender
  3. On loan acceptance, /stripe/disburse transfers funds from platform to borrower's bank (CLABE)
  4. Borrower calls /stripe/repayment → PaymentIntent charges borrower's card →
     Transfer to lender's Connected Account
  5. All operations persisted in SQL via sp_stripe_connectedAccounts / sp_stripe_transactions

SQL stored procedures expected (create in Azure SQL):
  sp_stripe_connectedAccounts  @pjsonfile  — action 1=upsert, 2=get by clientId
  sp_stripe_transactions        @pjsonfile  — action 1=insert, 2=update status, 3=list
"""

import os
import json
import stripe
from fastapi import Request
from fastapi.responses import JSONResponse
from databases import connection
from datetime import datetime
from modules.walletBalance import debit_wallet

stripe.api_key = os.getenv("STRIPE_SECRET_KEY", "")
WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "")

# ── helpers ──────────────────────────────────────────────────────────────────

def _conn():
    return connection()

def _sp_connected_accounts(payload: dict):
    """Persist / retrieve Connected Account records via SP."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_stripe_connectedAccounts] @pjsonfile = %s",
            (json.dumps({"stripeAccounts": [payload]}),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        print(f"[stripe][sp_connected_accounts] DB error: {e}")
        return {}
    finally:
        if conn:
            conn.close()

def _sp_transaction(payload: dict):
    """Persist / retrieve payment transaction records via SP."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_stripe_transactions] @pjsonfile = %s",
            (json.dumps({"stripeTransactions": [payload]}),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        print(f"[stripe][sp_transaction] DB error: {e}")
        return {}
    finally:
        if conn:
            conn.close()

def _external_account_info(acct):
    """
    Extract bank-account/debit-card payout info from a Stripe Account object.
    Caller must have retrieved `acct` with expand=["external_accounts"].
    """
    ext = getattr(acct, "external_accounts", None)
    data = getattr(ext, "data", []) if ext else []
    if not data:
        return False, None, None, None
    first = data[0]
    ext_type = getattr(first, "object", None)  # "bank_account" | "card"
    last4 = getattr(first, "last4", None)
    bank_name = getattr(first, "bank_name", None) if ext_type == "bank_account" else getattr(first, "brand", None)
    return True, last4, ext_type, bank_name


def _persist_and_serialize(acct, client_id: int, company_id: int) -> dict:
    """Upsert the connected account's live status into SQL (via SP) and return
    the ConnectedAccount shape the mobile app expects. `acct` must be retrieved
    with expand=["external_accounts"]."""
    charges   = getattr(acct, "charges_enabled", False)
    payouts   = getattr(acct, "payouts_enabled", False)
    submitted = getattr(acct, "details_submitted", False)
    has_ext, ext_last4, ext_type, ext_bank = _external_account_info(acct)
    _sp_connected_accounts({
        "action": "upsert",
        "clientId": client_id,
        "companyId": company_id,
        "connectedAccountId": acct["id"],
        "chargesEnabled": charges,
        "payoutsEnabled": payouts,
        "detailsSubmitted": submitted,
        "hasExternalAccount": has_ext,
        "externalAccountLast4": ext_last4,
        "externalAccountType": ext_type,
        "externalAccountBankName": ext_bank,
    })
    return {
        "connectedAccountId": acct["id"],
        "clientId": client_id,
        "companyId": company_id,
        "chargesEnabled": charges,
        "payoutsEnabled": payouts,
        "detailsSubmitted": submitted,
        "hasExternalAccount": has_ext,
        "externalAccountLast4": ext_last4,
        "externalAccountType": ext_type,
        "externalAccountBankName": ext_bank,
    }


def _sp_transactions_list(company_id: int, filters: dict = None):
    """List transactions from SQL."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        payload = {"action": "list", "companyId": company_id, **(filters or {})}
        cursor.execute(
            "EXEC [dbo].[sp_stripe_transactions] @pjsonfile = %s",
            (json.dumps({"stripeTransactions": [payload]}),)
        )
        rows = cursor.fetchall()
        json_result = "".join(r[0] for r in rows if r and r[0])
        return json.loads(json_result) if json_result else {"transactions": []}
    except Exception as e:
        print(f"[stripe][sp_transactions_list] DB error: {e}")
        return {"transactions": []}
    finally:
        if conn:
            conn.close()

# ── Connected Accounts ───────────────────────────────────────────────────────

async def create_connected_account(payload: dict):
    """Create or retrieve a Stripe **Custom** connected account for a client.

    Custom, not Express: onboarding happens through our own native forms via
    submit_connected_account_kyc, which only a Custom account permits. Accounts
    predating that switch are Express and get replaced here — see below.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    email      = payload.get("email", f"client{client_id}@posgmo.mx")

    print(
        f"[stripe][create_connected_account] start "
        f"clientId={client_id} companyId={company_id} email={email}"
    )

    if not client_id or not company_id:
        print("[stripe][create_connected_account] missing required fields")
        return JSONResponse({"error": "clientId and companyId required"}, status_code=400)

    acct_id = None
    try:
        # Check if already exists in SQL
        existing = _sp_connected_accounts({"action": "get", "clientId": client_id, "companyId": company_id})
        print(
            f"[stripe][create_connected_account] existing type={type(existing).__name__} "
            f"value={existing}"
        )

        if not isinstance(existing, dict):
            print(
                "[stripe][create_connected_account] unexpected existing payload from DB; "
                "forcing empty dict fallback"
            )
            existing = {}

        acct_id = existing.get("connectedAccountId")
        print(f"[stripe][create_connected_account] acct_id from DB={acct_id}")

        if not acct_id:
            # Create a new Stripe **Custom** account — onboarded entirely through
            # our own native forms + API (submit_connected_account_kyc /
            # attach_external_bank_account), no connect.stripe.com redirect. Only
            # `transfers` is requested: these accounts are payout recipients and
            # card charges route through the platform via destination charges.
            print("[stripe][create_connected_account] creating new Stripe custom account")
            acct = stripe.Account.create(
                type="custom",
                country="MX",
                email=email,
                capabilities={
                    "transfers": {"requested": True},
                },
                business_type="individual",
                metadata={"clientId": str(client_id), "companyId": str(company_id)},
            )
            acct_id = acct["id"]
            print(f"[stripe][create_connected_account] stripe account created acct_id={acct_id}")

            # Persist to SQL — _sp_connected_accounts swallows DB errors and
            # returns {} on failure, so we must confirm the row actually
            # landed before reporting success. Otherwise the Stripe account
            # exists but is unreachable (every later lookup finds nothing,
            # and every retry mints another orphaned Stripe account).
            print("[stripe][create_connected_account] persisting new account status in SQL")
            persisted = _sp_connected_accounts({
                "action": "upsert",
                "clientId": client_id,
                "companyId": company_id,
                "connectedAccountId": acct_id,
                "chargesEnabled": False,
                "payoutsEnabled": False,
                "detailsSubmitted": False,
                "hasExternalAccount": False,
            })
            if not isinstance(persisted, dict) or persisted.get("connectedAccountId") != acct_id:
                print(
                    f"[stripe][create_connected_account] SQL persist FAILED to confirm "
                    f"acct_id={acct_id} clientId={client_id} companyId={company_id} persisted={persisted}"
                )
                return JSONResponse(
                    {"error": "Stripe account created but could not be saved. Please retry."},
                    status_code=500,
                )

            return JSONResponse({
                "account": {
                    "connectedAccountId": acct_id,
                    "clientId": client_id,
                    "companyId": company_id,
                    "chargesEnabled": False,
                    "payoutsEnabled": False,
                    "detailsSubmitted": False,
                    "hasExternalAccount": False,
                    "externalAccountLast4": None,
                    "externalAccountType": None,
                    "externalAccountBankName": None,
                }
            }, status_code=200)

        # Account exists — refresh status from Stripe
        print(f"[stripe][create_connected_account] retrieving existing Stripe account acct_id={acct_id}")
        acct = stripe.Account.retrieve(acct_id, expand=["external_accounts"])

        # Accounts created before the native-onboarding switch are Express.
        # Stripe only lets a platform set business_type / individual /
        # tos_acceptance on **Custom** accounts — on Express it collects those
        # through its own hosted flow — so submit_connected_account_kyc against
        # one fails with:
        #   oauth_not_supported: This application does not have the required
        #   permissions for the parameters 'business_type', 'individual',
        #   'tos_acceptance' on account 'acct_...'
        # and the client can never finish onboarding in the app. Stripe cannot
        # convert an account's type, so the only remedy is a fresh account.
        # Without this check the stale id is reused forever and every KYC
        # submission 400s with an error that says nothing about the real cause.
        acct_type = getattr(acct, "type", None)
        if acct_type != "custom":
            _stale_submitted = getattr(acct, "details_submitted", False)
            _stale_has_ext, _, _, _ = _external_account_info(acct)
            if _stale_submitted or _stale_has_ext:
                # The old account carries real onboarding data or a bank
                # account. Replacing it here would silently strand that, so
                # report it and let it be handled deliberately.
                print(
                    "[stripe][create_connected_account] REFUSING to replace non-custom account "
                    f"acct_id={acct_id} type={acct_type} — it has onboarding data "
                    f"(details_submitted={_stale_submitted} hasExternalAccount={_stale_has_ext}). "
                    "Native KYC cannot work against it; migrate this client manually."
                )
                return JSONResponse({
                    "error": (
                        f"Connected account {acct_id} is a '{acct_type}' account with existing "
                        "onboarding data. Native KYC requires a Custom account and Stripe cannot "
                        "convert account types; this client needs manual migration."
                    )
                }, status_code=409)

            print(
                f"[stripe][create_connected_account] stale non-custom account acct_id={acct_id} "
                f"type={acct_type} with no onboarding data — replacing with a new custom account"
            )
            acct = stripe.Account.create(
                type="custom",
                country="MX",
                email=email,
                capabilities={
                    "transfers": {"requested": True},
                },
                business_type="individual",
                metadata={
                    "clientId": str(client_id),
                    "companyId": str(company_id),
                    "replaces": acct_id,
                },
            )
            acct_id = acct["id"]
            print(
                f"[stripe][create_connected_account] replacement custom account created acct_id={acct_id}"
            )

        _charges   = getattr(acct, "charges_enabled", False)
        _payouts   = getattr(acct, "payouts_enabled", False)
        _submitted = getattr(acct, "details_submitted", False)
        _has_ext, _ext_last4, _ext_type, _ext_bank = _external_account_info(acct)
        print(
            "[stripe][create_connected_account] stripe retrieve success "
            f"charges_enabled={_charges} payouts_enabled={_payouts} details_submitted={_submitted} "
            f"hasExternalAccount={_has_ext}"
        )
        _sp_connected_accounts({
            "action": "upsert",
            "clientId": client_id,
            "companyId": company_id,
            "connectedAccountId": acct_id,
            "chargesEnabled": _charges,
            "payoutsEnabled": _payouts,
            "detailsSubmitted": _submitted,
            "hasExternalAccount": _has_ext,
            "externalAccountLast4": _ext_last4,
            "externalAccountType": _ext_type,
            "externalAccountBankName": _ext_bank,
        })
        return JSONResponse({
            "account": {
                "connectedAccountId": acct_id,
                "clientId": client_id,
                "companyId": company_id,
                "chargesEnabled": _charges,
                "payoutsEnabled": _payouts,
                "detailsSubmitted": _submitted,
                "hasExternalAccount": _has_ext,
                "externalAccountLast4": _ext_last4,
                "externalAccountType": _ext_type,
                "externalAccountBankName": _ext_bank,
            }
        }, status_code=200)

    except stripe.StripeError as e:
        print(
            f"[stripe][create_connected_account] Stripe error type={type(e).__name__} "
            f"clientId={client_id} companyId={company_id} acct_id={acct_id} error={e}"
        )
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        print(
            f"[stripe][create_connected_account] Error type={type(e).__name__} "
            f"clientId={client_id} companyId={company_id} acct_id={acct_id} error={repr(e)}"
        )
        return JSONResponse({"error": str(e)}, status_code=500)


async def get_connected_account_status(payload: dict):
    """Return current KYC/charges status for a client's Connected Account."""
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")

    print(f"[stripe][get_connected_account_status] start clientId={client_id} companyId={company_id}")

    acct_id = None
    try:
        existing = _sp_connected_accounts({"action": "get", "clientId": client_id, "companyId": company_id})
        print(
            f"[stripe][get_connected_account_status] existing type={type(existing).__name__} "
            f"value={existing}"
        )

        if not isinstance(existing, dict):
            print(
                "[stripe][get_connected_account_status] unexpected existing payload from DB; "
                "forcing empty dict fallback"
            )
            existing = {}

        acct_id = existing.get("connectedAccountId")
        print(f"[stripe][get_connected_account_status] acct_id from DB={acct_id}")

        if not acct_id:
            print("[stripe][get_connected_account_status] no connected account found in DB")
            return JSONResponse({"account": None}, status_code=200)

        print(f"[stripe][get_connected_account_status] retrieving Stripe account acct_id={acct_id}")
        acct = stripe.Account.retrieve(acct_id, expand=["external_accounts"])
        charges_enabled   = getattr(acct, "charges_enabled", False)
        payouts_enabled   = getattr(acct, "payouts_enabled", False)
        details_submitted = getattr(acct, "details_submitted", False)
        has_ext, ext_last4, ext_type, ext_bank = _external_account_info(acct)

        print(
            "[stripe][get_connected_account_status] stripe retrieve success "
            f"charges_enabled={charges_enabled} payouts_enabled={payouts_enabled} "
            f"details_submitted={details_submitted} hasExternalAccount={has_ext}"
        )

        # Update SQL with latest status
        print("[stripe][get_connected_account_status] updating SQL account status")
        _sp_connected_accounts({
            "action": "upsert",
            "clientId": client_id,
            "companyId": company_id,
            "connectedAccountId": acct_id,
            "chargesEnabled": charges_enabled,
            "payoutsEnabled": payouts_enabled,
            "detailsSubmitted": details_submitted,
            "hasExternalAccount": has_ext,
            "externalAccountLast4": ext_last4,
            "externalAccountType": ext_type,
            "externalAccountBankName": ext_bank,
        })

        return JSONResponse({
            "account": {
                "connectedAccountId": acct_id,
                "clientId": client_id,
                "companyId": company_id,
                "chargesEnabled": charges_enabled,
                "payoutsEnabled": payouts_enabled,
                "detailsSubmitted": details_submitted,
                "hasExternalAccount": has_ext,
                "externalAccountLast4": ext_last4,
                "externalAccountType": ext_type,
                "externalAccountBankName": ext_bank,
            }
        }, status_code=200)

    except stripe.StripeError as e:
        print(
            f"[stripe][get_connected_account_status] Stripe error type={type(e).__name__} "
            f"clientId={client_id} companyId={company_id} acct_id={acct_id} error={e}"
        )
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        print(
            f"[stripe][get_connected_account_status] Error type={type(e).__name__} "
            f"clientId={client_id} companyId={company_id} acct_id={acct_id} error={repr(e)}"
        )
        return JSONResponse({"error": str(e)}, status_code=500)


# ── Native (redirect-free) onboarding ────────────────────────────────────────
# Replace the hosted /account-session and /onboarding-link flows for Custom
# accounts. The app collects KYC/bank data with native forms and submits it
# here; the user never leaves the app.

def _lookup_account_id(client_id, company_id):
    existing = _sp_connected_accounts({"action": "get", "clientId": client_id, "companyId": company_id})
    if not isinstance(existing, dict):
        return None
    return existing.get("connectedAccountId")


async def submit_connected_account_kyc(payload: dict):
    """Attach identity/tax info + ToS acceptance to a client's Custom account.

    Body: clientId, companyId, firstName, lastName, dobDay/Month/Year, email,
          phone?, taxId?, address{line1,city,state,postalCode,country}, acceptedTos,
          _ip (injected by the route — Stripe requires it for ToS acceptance).
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    if not client_id or not company_id:
        return JSONResponse({"error": "clientId and companyId required"}, status_code=400)

    acct_id = _lookup_account_id(client_id, company_id)
    if not acct_id:
        return JSONResponse({"error": "No connected account found. Create one first."}, status_code=404)

    addr = payload.get("address") or {}
    individual = {
        "first_name": payload.get("firstName"),
        "last_name":  payload.get("lastName"),
        "email":      payload.get("email"),
        "dob": {
            "day":   payload.get("dobDay"),
            "month": payload.get("dobMonth"),
            "year":  payload.get("dobYear"),
        },
        "address": {
            "line1":       addr.get("line1"),
            "city":        addr.get("city"),
            "state":       addr.get("state"),
            "postal_code": addr.get("postalCode"),
            "country":     addr.get("country", "MX"),
        },
    }
    if payload.get("phone"):
        individual["phone"] = payload["phone"]
    if payload.get("taxId"):
        individual["id_number"] = payload["taxId"]

    modify_kwargs = {"individual": individual, "business_type": "individual"}
    if payload.get("acceptedTos"):
        modify_kwargs["tos_acceptance"] = {
            "date": int(datetime.utcnow().timestamp()),
            "ip":   payload.get("_ip") or "0.0.0.0",
        }

    try:
        stripe.Account.modify(acct_id, **modify_kwargs)
        acct = stripe.Account.retrieve(acct_id, expand=["external_accounts"])
        return JSONResponse({"account": _persist_and_serialize(acct, client_id, company_id)}, status_code=200)
    except stripe.StripeError as e:
        # oauth_not_supported here means the account is not Custom (almost
        # always an Express account created before the native-onboarding
        # switch). Stripe's own message names the rejected parameters but not
        # the cause, which sent a real debugging session looking at
        # permissions and API keys instead of the account type. See the
        # replacement logic in create_connected_account.
        if getattr(e, "code", None) == "oauth_not_supported":
            print(
                f"[stripe][submit_kyc] acct_id={acct_id} rejected platform-set KYC fields — this "
                "is not a Custom account, so Stripe will not let the platform set "
                "business_type/individual/tos_acceptance. Call /stripe/connected-accounts first "
                "to have it replaced with a Custom account."
            )
            return JSONResponse({
                "error": (
                    f"Connected account {acct_id} is not a Custom account, so native KYC cannot be "
                    "submitted against it. Re-run account creation to provision a Custom account."
                )
            }, status_code=409)
        print(f"[stripe][submit_kyc] Stripe error acct_id={acct_id} error={e}")
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        print(f"[stripe][submit_kyc] Error acct_id={acct_id} error={repr(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)


async def attach_external_bank_account(payload: dict):
    """Attach a payout destination to a client's Custom account.

    `bankToken` is a Stripe.js token created client-side — EITHER a bank_account
    token (btok_, from a CLABE) OR a debit-card token (tok_, from reusing the
    CardElement). Stripe accepts both as external accounts (card = instant payout).
    Body: clientId, companyId, bankToken.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    bank_token = payload.get("bankToken")
    if not client_id or not company_id or not bank_token:
        return JSONResponse({"error": "clientId, companyId and bankToken required"}, status_code=400)

    acct_id = _lookup_account_id(client_id, company_id)
    if not acct_id:
        return JSONResponse({"error": "No connected account found. Create one first."}, status_code=404)

    try:
        stripe.Account.create_external_account(
            acct_id,
            external_account=bank_token,
            default_for_currency=True,
        )
        acct = stripe.Account.retrieve(acct_id, expand=["external_accounts"])
        return JSONResponse({"account": _persist_and_serialize(acct, client_id, company_id)}, status_code=200)
    except stripe.StripeError as e:
        print(f"[stripe][attach_bank] Stripe error acct_id={acct_id} error={e}")
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        print(f"[stripe][attach_bank] Error acct_id={acct_id} error={repr(e)}")
        return JSONResponse({"error": str(e)}, status_code=500)


async def create_account_session(payload: dict):
    """
    Create a Stripe Account Session so the client's KYC onboarding renders
    embedded inside the app (Connect embedded components) instead of
    redirecting to a Stripe-hosted URL in an external browser tab. Stripe
    still owns all compliance/validation logic — this just changes where
    the UI is displayed.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")

    try:
        existing = _sp_connected_accounts({"action": "get", "clientId": client_id, "companyId": company_id})
        acct_id = existing.get("connectedAccountId") if isinstance(existing, dict) else None

        if not acct_id:
            return JSONResponse({"error": "No connected account found. Create one first."}, status_code=404)

        session = stripe.AccountSession.create(
            account=acct_id,
            components={
                # external_account_collection already defaults to True — set
                # explicitly since the whole point of this step is capturing
                # the client's bank account/debit card for payouts.
                "account_onboarding": {
                    "enabled": True,
                    "features": {"external_account_collection": True},
                },
            },
        )

        return JSONResponse({"clientSecret": session["client_secret"]}, status_code=200)

    except stripe.StripeError as e:
        print(f"[stripe][create_account_session] Stripe error: {e}")
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        print(f"[stripe][create_account_session] Error: {e}")
        return JSONResponse({"error": str(e)}, status_code=500)


async def get_onboarding_link(payload: dict):
    """Generate a Stripe Express onboarding URL for KYC completion."""
    client_id   = payload.get("clientId")
    company_id  = payload.get("companyId")
    return_url  = payload.get("returnUrl", "https://posgmo.mx/p2p-lending")
    refresh_url = payload.get("refreshUrl", "https://posgmo.mx/payment")

    try:
        existing = _sp_connected_accounts({"action": "get", "clientId": client_id, "companyId": company_id})
        acct_id = existing.get("connectedAccountId")

        if not acct_id:
            return JSONResponse({"error": "No connected account found. Create one first."}, status_code=404)

        link = stripe.AccountLink.create(
            account=acct_id,
            refresh_url=refresh_url,
            return_url=return_url,
            type="account_onboarding",
        )

        return JSONResponse({"url": link["url"], "expiresAt": link["expires_at"]}, status_code=200)

    except stripe.StripeError as e:
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

# ── Payment Intents ──────────────────────────────────────────────────────────

async def create_payment_intent(payload: dict):
    """
    Create a Stripe PaymentIntent.

    Expected payload fields:
      companyId, fromClientId, toClientId, amount (centavos MXN),
      paymentType, loanId?, proposalId?, description?
    """
    company_id     = payload.get("companyId")
    from_client_id = payload.get("fromClientId")
    to_client_id   = payload.get("toClientId")
    amount         = int(payload.get("amount", 0))   # centavos
    payment_type   = payload.get("paymentType", "wallet_top_up")
    loan_id        = payload.get("loanId")
    proposal_id    = payload.get("proposalId")
    description    = payload.get("description", "P2P GMO Payment")
    metadata       = payload.get("metadata", {})

    if not stripe.api_key or stripe.api_key.startswith("sk_test_YOUR"):
        # Stripe not configured — return a mock client secret for development
        mock_intent_id = f"pi_mock_{int(datetime.utcnow().timestamp())}"
        return JSONResponse({
            "clientSecret": f"{mock_intent_id}_secret_mock",
            "paymentIntentId": mock_intent_id,
            "transactionId": 0,
            "amount": amount,
            "currency": "mxn",
        }, status_code=200)

    if amount < 100:  # Stripe minimum ~$1 MXN
        return JSONResponse({"error": "Monto mínimo: $1.00 MXN"}, status_code=400)

    try:
        intent = stripe.PaymentIntent.create(
            amount=amount,
            currency="mxn",
            description=description,
            metadata={
                "companyId": str(company_id),
                "fromClientId": str(from_client_id),
                "toClientId": str(to_client_id),
                "paymentType": payment_type,
                "loanId": str(loan_id or ""),
                "proposalId": str(proposal_id or ""),
                **metadata,
            },
            payment_method_types=["card", "oxxo"],
            payment_method_options={
                "oxxo": {"expires_after_days": 3},
            },
        )

        # Persist transaction record in SQL (status=pending)
        tx = _sp_transaction({
            "action": "insert",
            "companyId": company_id,
            "fromClientId": from_client_id,
            "toClientId": to_client_id,
            "amount": amount,
            "currency": "mxn",
            "paymentType": payment_type,
            "status": "pending",
            "stripePaymentIntentId": intent["id"],
            "loanId": loan_id,
            "proposalId": proposal_id,
        })

        return JSONResponse({
            "clientSecret": intent["client_secret"],
            "paymentIntentId": intent["id"],
            "transactionId": tx.get("transactionId", 0),
            "amount": amount,
            "currency": "mxn",
        }, status_code=200)

    except stripe.StripeError as e:
        print(f"[stripe][create_payment_intent] Stripe error: {e}")
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        print(f"[stripe][create_payment_intent] Error: {e}")
        return JSONResponse({"error": str(e)}, status_code=500)


async def confirm_payment_intent(payload: dict):
    """
    Verify a PaymentIntent succeeded (called by frontend after confirmation).
    Updates SQL transaction status to 'succeeded'.
    """
    payment_intent_id = payload.get("paymentIntentId")
    company_id        = payload.get("companyId")

    if not payment_intent_id:
        return JSONResponse({"error": "paymentIntentId required"}, status_code=400)

    try:
        if payment_intent_id.startswith("pi_mock_"):
            # Development mock — skip Stripe verification
            tx = _sp_transaction({
                "action": "update_status",
                "stripePaymentIntentId": payment_intent_id,
                "status": "succeeded",
                "companyId": company_id,
            })
            return JSONResponse({"status": "succeeded", "stripePaymentIntentId": payment_intent_id, **tx}, status_code=200)

        intent = stripe.PaymentIntent.retrieve(payment_intent_id)
        status = intent.get("status")

        tx = _sp_transaction({
            "action": "update_status",
            "stripePaymentIntentId": payment_intent_id,
            "status": status,
            "companyId": company_id,
        })

        if status != "succeeded":
            return JSONResponse({"error": f"Payment status: {status}"}, status_code=400)

        return JSONResponse({"status": status, "stripePaymentIntentId": payment_intent_id, **tx}, status_code=200)

    except stripe.StripeError as e:
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

# ── Disbursement ─────────────────────────────────────────────────────────────

async def disburse_loan(payload: dict):
    """
    Transfer funds from platform to borrower after loan approval.
    Assumes lender's wallet top-up already charged their card.
    """
    company_id  = payload.get("companyId")
    loan_id     = payload.get("loanId")
    proposal_id = payload.get("proposalId")
    lender_id   = payload.get("lenderId")
    borrower_id = payload.get("borrowerId")
    amount_mxn  = float(payload.get("amount", 0))
    amount_centavos = int(amount_mxn * 100)

    if not stripe.api_key or stripe.api_key.startswith("sk_test_YOUR"):
        # Dev mock
        return JSONResponse({
            "status": "succeeded",
            "transactionId": 0,
            "stripeTransferId": f"tr_mock_{int(datetime.utcnow().timestamp())}",
            "amount": amount_centavos,
            "currency": "mxn",
        }, status_code=200)

    try:
        # Get borrower's connected account
        borrower_acct = _sp_connected_accounts({"action": "get", "clientId": borrower_id, "companyId": company_id})
        borrower_acct_id = borrower_acct.get("connectedAccountId")

        if not borrower_acct_id:
            return JSONResponse({"error": "Prestatario no tiene cuenta bancaria registrada con Stripe."}, status_code=400)

        transfer = stripe.Transfer.create(
            amount=amount_centavos,
            currency="mxn",
            destination=borrower_acct_id,
            metadata={
                "companyId": str(company_id),
                "loanId": str(loan_id or ""),
                "lenderId": str(lender_id),
                "borrowerId": str(borrower_id),
                "type": "loan_disbursement",
            },
        )

        tx = _sp_transaction({
            "action": "insert",
            "companyId": company_id,
            "fromClientId": lender_id,
            "toClientId": borrower_id,
            "amount": amount_centavos,
            "currency": "mxn",
            "paymentType": "loan_disbursement",
            "status": "succeeded",
            "stripeTransferId": transfer["id"],
            "loanId": loan_id,
            "proposalId": proposal_id,
        })

        return JSONResponse({
            "status": "succeeded",
            "transactionId": tx.get("transactionId", 0),
            "stripeTransferId": transfer["id"],
            "amount": amount_centavos,
            "currency": "mxn",
        }, status_code=200)

    except stripe.StripeError as e:
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

# ── Withdrawal ───────────────────────────────────────────────────────────────

async def withdraw_to_bank(payload: dict):
    """
    On-demand payout of a client's available wallet balance to their linked
    bank account/debit card. Connected accounts stay on Stripe's default
    automatic payout schedule (a borrower's loan disbursement should reach
    their bank promptly, not sit until a manual pull) — this just lets a
    client trigger an extra payout of whatever's currently on their
    Connected Account balance right now, instead of waiting for the next
    automatic cycle.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    amount_mxn = float(payload.get("amount", 0))
    amount_centavos = int(amount_mxn * 100)

    if not client_id or not company_id or amount_mxn <= 0:
        return JSONResponse({"error": "clientId, companyId y un monto positivo son requeridos"}, status_code=400)

    try:
        existing = _sp_connected_accounts({"action": "get", "clientId": client_id, "companyId": company_id})
        acct_id = existing.get("connectedAccountId") if isinstance(existing, dict) else None
        has_ext = existing.get("hasExternalAccount") if isinstance(existing, dict) else False

        if not acct_id or not has_ext:
            return JSONResponse({"error": "El cliente no tiene una cuenta bancaria o tarjeta vinculada."}, status_code=400)

        # Debit the SQL ledger first — has its own insufficient-balance guard,
        # so a bad withdrawal request never reaches Stripe at all.
        debit_res = await debit_wallet({
            "clientId": client_id, "companyId": company_id,
            "amountMXN": amount_mxn, "type": "withdrawal",
        })
        debit_body = json.loads(debit_res.body)
        if debit_body.get("error"):
            return JSONResponse({"error": debit_body["error"]}, status_code=400)

        if not stripe.api_key or stripe.api_key.startswith("sk_test_YOUR"):
            payout_id = f"po_mock_{int(datetime.utcnow().timestamp())}"
        else:
            payout = stripe.Payout.create(
                amount=amount_centavos,
                currency="mxn",
                stripe_account=acct_id,
            )
            payout_id = payout["id"]

        tx = _sp_transaction({
            "action": "insert",
            "companyId": company_id,
            "fromClientId": client_id,
            "toClientId": client_id,
            "amount": amount_centavos,
            "currency": "mxn",
            "paymentType": "wallet_withdrawal",
            "status": "succeeded",
            "stripePayoutId": payout_id,
        })

        return JSONResponse({
            "status": "succeeded",
            "transactionId": tx.get("transactionId", 0),
            "stripePayoutId": payout_id,
            "amount": amount_centavos,
            "currency": "mxn",
        }, status_code=200)

    except stripe.StripeError as e:
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)

# ── Transactions list ────────────────────────────────────────────────────────

async def list_transactions(payload: dict):
    company_id = payload.get("companyId")
    client_id  = payload.get("clientId")
    loan_id    = payload.get("loanId")
    payment_type = payload.get("paymentType")
    result = _sp_transactions_list(company_id, {
        k: v for k, v in {"clientId": client_id, "loanId": loan_id, "paymentType": payment_type}.items() if v
    })
    return JSONResponse(result, status_code=200)

# ── Webhook ──────────────────────────────────────────────────────────────────

async def handle_webhook(request: Request):
    """
    Stripe webhook — validates signature and handles events.
    Register in Stripe Dashboard → Developers → Webhooks:
      URL: https://smartloansbackend.azurewebsites.net/stripe/webhook
      Events: payment_intent.succeeded, payment_intent.payment_failed,
              account.updated
    """
    payload_bytes = await request.body()
    sig_header    = request.headers.get("stripe-signature", "")

    if not WEBHOOK_SECRET or WEBHOOK_SECRET.startswith("whsec_YOUR"):
        # Webhook secret not configured — parse without verification (dev only)
        event = json.loads(payload_bytes)
    else:
        try:
            event = stripe.Webhook.construct_event(payload_bytes, sig_header, WEBHOOK_SECRET)
        except stripe.SignatureVerificationError as e:
            print(f"[stripe][webhook] Signature verification failed: {e}")
            return JSONResponse({"error": "Invalid signature"}, status_code=400)

    event_type = event.get("type", "")
    data_obj   = event.get("data", {}).get("object", {})

    print(f"[stripe][webhook] Received event: {event_type}")

    if event_type == "payment_intent.succeeded":
        intent_id = data_obj.get("id")
        metadata  = data_obj.get("metadata", {})
        _sp_transaction({
            "action": "update_status",
            "stripePaymentIntentId": intent_id,
            "status": "succeeded",
            "companyId": metadata.get("companyId"),
        })
        print(f"[stripe][webhook] PaymentIntent succeeded: {intent_id}")

    elif event_type == "payment_intent.payment_failed":
        intent_id      = data_obj.get("id")
        failure_reason = data_obj.get("last_payment_error", {}).get("message", "payment failed")
        metadata       = data_obj.get("metadata", {})
        _sp_transaction({
            "action": "update_status",
            "stripePaymentIntentId": intent_id,
            "status": "failed",
            "failureReason": failure_reason,
            "companyId": metadata.get("companyId"),
        })
        print(f"[stripe][webhook] PaymentIntent failed: {intent_id} — {failure_reason}")

    elif event_type == "account.updated":
        acct_id           = data_obj.get("id")
        charges_enabled   = data_obj.get("charges_enabled", False)
        payouts_enabled   = data_obj.get("payouts_enabled", False)
        details_submitted = data_obj.get("details_submitted", False)
        metadata          = data_obj.get("metadata", {})
        client_id         = metadata.get("clientId")
        company_id        = metadata.get("companyId")
        if client_id:
            _sp_connected_accounts({
                "action": "upsert",
                "clientId": int(client_id),
                "companyId": int(company_id or 0),
                "connectedAccountId": acct_id,
                "chargesEnabled": charges_enabled,
                "payoutsEnabled": payouts_enabled,
                "detailsSubmitted": details_submitted,
            })
        print(f"[stripe][webhook] Account updated: {acct_id} charges={charges_enabled}")

    return JSONResponse({"received": True}, status_code=200)
