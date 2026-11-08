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
import threading
import stripe
from fastapi import Request
from fastapi.responses import JSONResponse
from databases import connection
from datetime import datetime
from modules.walletBalance import debit_wallet
from modules.walletTransactions import post_entry
from modules.companies import company_name
from modules.companyPaymentAccounts import (
    PLATFORM_ACCOUNT, active_stripe_account, add_stripe_account, confirm_account, list_accounts, platform_allowed,
    sync_charges_enabled, WALLET_TOPUP_PURPOSE,
)
from observability.logger import log_workflow_step, log_integration

stripe.api_key = os.getenv("STRIPE_SECRET_KEY", "")
WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "")
# Connect endpoints have their own signing secret in the Stripe Dashboard.
CONNECT_WEBHOOK_SECRET = os.getenv("STRIPE_CONNECT_WEBHOOK_SECRET", "")

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


def _persist_and_serialize(acct, client_id: int, company_id: int,
                           tos_accepted_at: str = None) -> dict:
    """Upsert the connected account's live status into SQL (via SP) and return
    the ConnectedAccount shape the mobile app expects. `acct` must be retrieved
    with expand=["external_accounts"].

    tos_accepted_at: ISO timestamp, passed ONLY by submit_connected_account_kyc
    right after Stripe accepts tos_acceptance — mirrors that legal record into
    our own DB (sp_stripe_connectedAccounts.tosAccepted/tosAcceptedAt) so it's
    visible without a Stripe API call. Other callers (create/attach) omit it;
    the SP's upsert is sticky and never un-sets an already-accepted flag."""
    charges   = getattr(acct, "charges_enabled", False)
    payouts   = getattr(acct, "payouts_enabled", False)
    submitted = getattr(acct, "details_submitted", False)
    has_ext, ext_last4, ext_type, ext_bank = _external_account_info(acct)
    # Whether the KYC identity step is already done, so the app can SKIP re-asking
    # for name/DOB/address on reload and jump straight to the payout step. Stripe
    # is the source of truth: once submit_connected_account_kyc runs, the account's
    # `individual` carries the submitted name (and Stripe stops listing those
    # fields as currently_due). details_submitted stays False until the external
    # account is also attached, so it can't stand in for "identity done".
    individual = getattr(acct, "individual", None)
    identity_submitted = bool(individual and getattr(individual, "first_name", None))
    upsert_payload = {
        "action": "upsert",
        "clientId": client_id,
        "companyId": company_id,
        "connectedAccountId": acct["id"],
        "chargesEnabled": charges,
        "payoutsEnabled": payouts,
        "detailsSubmitted": submitted,
        "identitySubmitted": identity_submitted,
        "hasExternalAccount": has_ext,
        "externalAccountLast4": ext_last4,
        "externalAccountType": ext_type,
        "externalAccountBankName": ext_bank,
    }
    if tos_accepted_at:
        upsert_payload["tosAccepted"] = True
        upsert_payload["tosAcceptedAt"] = tos_accepted_at
    saved = _sp_connected_accounts(upsert_payload)
    return {
        "connectedAccountId": acct["id"],
        "clientId": client_id,
        "companyId": company_id,
        "chargesEnabled": charges,
        "payoutsEnabled": payouts,
        "detailsSubmitted": submitted,
        "identitySubmitted": identity_submitted,
        "hasExternalAccount": has_ext,
        "externalAccountLast4": ext_last4,
        "externalAccountType": ext_type,
        "externalAccountBankName": ext_bank,
        "tosAccepted": saved.get("tosAccepted") if isinstance(saved, dict) else None,
        "tosAcceptedAt": saved.get("tosAcceptedAt") if isinstance(saved, dict) else None,
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

        # _persist_and_serialize (not a hand-built dict) so the response and the
        # SQL upsert both carry identitySubmitted — the app's resume logic
        # (startAtPayout) reads it from this endpoint, and hand-building the
        # payload here silently dropped it.
        account = _persist_and_serialize(acct, client_id, company_id)
        print(
            "[stripe][get_connected_account_status] stripe retrieve success "
            f"charges_enabled={account['chargesEnabled']} payouts_enabled={account['payoutsEnabled']} "
            f"details_submitted={account['detailsSubmitted']} "
            f"identity_submitted={account['identitySubmitted']} hasExternalAccount={account['hasExternalAccount']}"
        )

        return JSONResponse({"account": account}, status_code=200)

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

    # Stripe MX requires business_profile.url before enabling charges — without
    # it the account sits in requirements.past_due forever (this is what kept
    # charges_enabled=False even after full identity + bank onboarding). For
    # individuals with no website Stripe accepts product_description instead;
    # a real platform URL can be supplied via STRIPE_BUSINESS_PROFILE_URL.
    business_profile = {
        "product_description": (
            "Préstamos personales entre particulares (P2P) gestionados a "
            "través de la plataforma SmartLoans."
        ),
    }
    if os.getenv("STRIPE_BUSINESS_PROFILE_URL"):
        business_profile["url"] = os.getenv("STRIPE_BUSINESS_PROFILE_URL")

    modify_kwargs = {
        "individual": individual,
        "business_type": "individual",
        "business_profile": business_profile,
    }
    tos_accepted_at = None
    if payload.get("acceptedTos"):
        tos_now = datetime.utcnow()
        modify_kwargs["tos_acceptance"] = {
            "date": int(tos_now.timestamp()),
            "ip":   payload.get("_ip") or "0.0.0.0",
        }
        # Mismo instante enviado a Stripe (fuente legal) — se refleja en
        # nuestra DB vía _persist_and_serialize más abajo.
        tos_accepted_at = tos_now.isoformat()

    try:
        stripe.Account.modify(acct_id, **modify_kwargs)
        acct = stripe.Account.retrieve(acct_id, expand=["external_accounts"])
        return JSONResponse({"account": _persist_and_serialize(
            acct, client_id, company_id, tos_accepted_at=tos_accepted_at)}, status_code=200)
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

# ── Company accounts (RFC-010) ───────────────────────────────────────────────

def _company_stripe_account(company_id) -> str:
    """The company's own Stripe account id, PLATFORM_ACCOUNT, or "" (top-ups off)."""
    return active_stripe_account({"companyId": company_id, "purpose": WALLET_TOPUP_PURPOSE})


def _on(account: str) -> dict:
    """Stripe call kwargs for a top-up account: none for the platform's own."""
    return {"stripe_account": account} if account and account != PLATFORM_ACCOUNT else {}


def _company_customer(stripe_account: str, client_id, company_id=None) -> str:
    """The client's Customer on the account the top-up is charged on, where saved
    cards live, or "" if it can't be resolved: the top-up still goes through, only
    saving the card is lost. On the platform account the company is part of the
    match, so a top-up never picks up a Customer made for something else."""
    try:
        client = int(client_id)
        query = f"metadata['clientId']:'{client}'"
        metadata = {"clientId": str(client)}
        if stripe_account == PLATFORM_ACCOUNT:
            company = int(company_id)
            query += f" AND metadata['topUpCompanyId']:'{company}'"
            metadata["topUpCompanyId"] = str(company)
        found = stripe.Customer.search(query=query, limit=1, **_on(stripe_account))
        if found["data"]:
            return found["data"][0]["id"]
        return stripe.Customer.create(metadata=metadata, **_on(stripe_account),
                                      idempotency_key=f"customer-{stripe_account}-{company_id or ''}-{client}")["id"]
    except Exception as e:
        print(f"[stripe][company] customer lookup failed clientId={client_id}: {e}")
        return ""


async def answer_save_card(payload: dict):
    """After a top-up the client chooses whether to keep the card. Stripe can only
    keep a card if the charge was set up for it, so a "no" removes it here."""
    intent_id = payload.get("paymentIntentId")
    if not intent_id:
        return JSONResponse({"error": "paymentIntentId required"}, status_code=400)
    try:
        acct = _intent_account(payload.get("companyId"), payload.get("stripeAccount"))
        if not acct:
            return JSONResponse({"error": "Compañía sin cuenta Stripe activa"}, status_code=400)
        intent = stripe.PaymentIntent.retrieve(intent_id, **_on(acct))
        if intent["metadata"]["paymentType"] != LAUNDRY_TOP_UP or (
                acct == PLATFORM_ACCOUNT and intent["metadata"].get("companyId") != str(payload.get("companyId"))):
            return JSONResponse({"error": "Pago no válido"}, status_code=400)
        keep = payload.get("save") is True
        if not keep and intent["payment_method"]:
            stripe.PaymentMethod.detach(intent["payment_method"], **_on(acct))
        log_workflow_step("Top-up Card Choice", workflow_name="money_trail", action=LAUNDRY_TOP_UP,
                          entity="stripeTransactions", message=f"intent {intent_id} keep={keep}")
        return JSONResponse({"saved": keep}, status_code=200)
    except stripe.StripeError as e:
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def _intent_account(company_id, requested: str = None) -> str:
    """The account a top-up was charged on. The app sends back the one it paid
    on, because the company's ACTIVE account can change after the charge; it only
    counts if that company owns it, archived accounts included."""
    if requested and any(a.get("stripeConnectedAccountId") == requested
                         for a in list_accounts({"companyId": company_id})):
        return requested
    return _company_stripe_account(company_id)


def _refresh_pending_accounts(rows: list) -> list:
    """Reads Stripe directly, so the admin isn't left waiting on a webhook after
    finishing onboarding. Rows that are already enabled are left alone."""
    for row in rows:
        acct_id = row.get("stripeConnectedAccountId")
        if row.get("accountStatus") != "PENDING_VERIFICATION" or row.get("chargesEnabled") or not acct_id:
            continue
        try:
            enabled = bool(stripe.Account.retrieve(acct_id)["charges_enabled"])
            if enabled:
                sync_charges_enabled({"stripeConnectedAccountId": acct_id, "chargesEnabled": True})
                row["chargesEnabled"] = True
        except stripe.StripeError as e:
            print(f"[stripe][company] refresh failed acct={acct_id}: {e}")
    return rows


async def list_company_accounts(payload: dict):
    row = (payload.get("companyPaymentAccounts") or [{}])[0]
    try:
        rows = _refresh_pending_accounts(list_accounts({"companyId": row.get("companyId")}))
        return JSONResponse({"companyPaymentAccounts": rows,
                             "platformTopUpAllowed": platform_allowed(row.get("companyId"))}, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


async def confirm_company_account(payload: dict):
    row = (payload.get("companyPaymentAccounts") or [{}])[0]
    try:
        _refresh_pending_accounts(list_accounts({"companyId": row.get("companyId")}))
        return confirm_account(row)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


async def company_onboarding_link(payload: dict):
    """Creates or reuses the company's Stripe account and returns its onboarding
    URL. A Standard account makes the company the merchant of record: it has its
    own Stripe dashboard and receives its own payouts."""
    row = (payload.get("companyPaymentAccounts") or [{}])[0]
    company_id = row.get("companyId")
    user_id = row.get("createdByUserId")
    return_url = row.get("returnUrl")
    if not company_id or not user_id or not return_url:
        return JSONResponse({"error": "companyId, createdByUserId and returnUrl required"}, status_code=400)
    try:
        rows = [a for a in list_accounts({"companyId": company_id})
                if a.get("accountType") == "stripe_connect" and a.get("purpose") == WALLET_TOPUP_PURPOSE]
        # replaceActive starts a new account; the old one keeps charging until a
        # second admin confirms the new one, which archives it.
        reusable = ("PENDING_VERIFICATION",) if row.get("replaceActive") else ("PENDING_VERIFICATION", "ACTIVE")
        existing = next((a for a in rows if a.get("accountStatus") in reusable), None)
        acct_id = existing.get("stripeConnectedAccountId") if existing else None
        if not acct_id:
            # Same key until a row is saved: a retry or a second admin gets this
            # same account back instead of creating another one in Stripe.
            acct = stripe.Account.create(type="standard", country="MX",
                                         metadata={"companyId": str(company_id)},
                                         idempotency_key=f"company-account-{company_id}-{len(rows)}")
            acct_id = acct["id"]
            try:
                added = add_stripe_account({
                    "companyId": company_id, "purpose": WALLET_TOPUP_PURPOSE, "stripeConnectedAccountId": acct_id,
                    "holderName": company_name({"companyId": company_id}) or f"Compañía {company_id}",
                    "createdByUserId": user_id,
                })
            except Exception as e:
                added = {"error": str(e)}
            saved = bool(added.get("companyPaymentAccountId")) or any(
                a.get("stripeConnectedAccountId") == acct_id for a in list_accounts({"companyId": company_id}))
            if not saved:
                # The account exists in Stripe but nothing points to it yet.
                print(f"[stripe][company] persist FAILED acct={acct_id} companyId={company_id}: {added}")
                return JSONResponse({"error": "No se pudo guardar la cuenta de Stripe."}, status_code=500)
            log_workflow_step("Company Stripe Account Created", workflow_name="money_trail",
                              action="company_account", entity="companyPaymentAccounts",
                              entity_id=added.get("companyPaymentAccountId"), message=f"companyId={company_id}")
        link = stripe.AccountLink.create(account=acct_id, refresh_url=return_url, return_url=return_url,
                                         type="account_onboarding")
        return JSONResponse({"url": link["url"]}, status_code=200)
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

    # RFC-010 (POSVending docs/rfcs): a card top-up is a direct charge on the company's
    # own connected Stripe account. A charge on the platform account would mean
    # SmartLoans holds customer money (against D1), so without an ACTIVE company
    # account it stays off. Intents created before this keep crediting on confirm.
    connected_account = _company_stripe_account(company_id) if payment_type == LAUNDRY_TOP_UP else None
    if payment_type == LAUNDRY_TOP_UP and not connected_account:
        return JSONResponse({
            "error": "laundry_card_topup_unavailable",
            "message": "La recarga con tarjeta no está disponible por ahora. Recarga en mostrador.",
        }, status_code=503)

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
        customer = _company_customer(connected_account, from_client_id, company_id) if connected_account else ""
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
            **({"customer": customer, "setup_future_usage": "off_session"} if customer else {}),
            **({**_on(connected_account), "payment_method_types": ["card"]} if connected_account
               else {"payment_method_types": ["card", "oxxo"],
                     "payment_method_options": {"oxxo": {"expires_after_days": 3}}}),
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

        # Rastro de dinero (observabilidad): integración Stripe + paso del workflow.
        log_integration("stripe", "payment_intent_create",
                        response={"paymentIntentId": intent["id"], "amountMXN": amount / 100.0})
        log_workflow_step("Payment Intent Created", workflow_name="money_trail", action=payment_type,
                          entity="stripeTransactions", entity_id=tx.get("transactionId"),
                          message=f"${amount / 100.0:,.2f} MXN {payment_type} — intent {intent['id']}")

        return JSONResponse({
            "clientSecret": intent["client_secret"],
            "paymentIntentId": intent["id"],
            "transactionId": tx.get("transactionId", 0),
            "amount": amount,
            "currency": "mxn",
            # The platform's own account is the app's default: it gets no stripeAccount.
            **({"canSaveCard": bool(customer), **({"stripeAccount": connected_account} if _on(connected_account) else {})}
               if connected_account else {}),
        }, status_code=200)

    except stripe.StripeError as e:
        print(f"[stripe][create_payment_intent] Stripe error: {e}")
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        print(f"[stripe][create_payment_intent] Error: {e}")
        return JSONResponse({"error": str(e)}, status_code=500)


# Fórmula publicada Stripe MX (fallback): 3.6% + $3 MXN + IVA 16% sobre la comisión.
_STRIPE_MX_PCT, _STRIPE_MX_FIXED, _IVA = 0.036, 3.0, 0.16


def _stripe_fee_and_net_mxn(intent, gross_mxn: float) -> tuple[float, float]:
    """(feeMXN, netMXN) REALES del balance transaction del cargo. Si el intent
    no está disponible/expandido, cae a la fórmula publicada de Stripe MX."""
    try:
        if intent is not None:
            charge = intent["latest_charge"]
            bt = charge["balance_transaction"] if charge else None
            if bt is not None and not isinstance(bt, str):
                return round(float(bt["fee"]) / 100.0, 2), round(float(bt["net"]) / 100.0, 2)
    except Exception as e:
        print(f"[stripe][fee] balance transaction unavailable, using formula: {e}")
    fee = round((gross_mxn * _STRIPE_MX_PCT + _STRIPE_MX_FIXED) * (1 + _IVA), 2)
    return fee, round(gross_mxn - fee, 2)


# Recarga del saldo prepago de la compañía: se acredita en walletTransactions,
# el mismo libro que /laundryDevices/authorize descuenta (LAUNDRY_USAGE). La
# cartera P2P (wallet_top_up) sigue en clientWallets — no se mezclan.
LAUNDRY_TOP_UP = "laundry_top_up"
_TOP_UP_TYPES = ("wallet_top_up", LAUNDRY_TOP_UP)


def _credited_mxn(tx: dict, gross_mxn: float, net_mxn: float) -> float:
    """What reaches the client's balance. A company saldo top-up credits the full
    amount paid and the company absorbs the fee (RFC-012, decision A); a P2P
    wallet top-up still credits the net."""
    return gross_mxn if isinstance(tx, dict) and tx.get("paymentType") == LAUNDRY_TOP_UP else net_mxn


def _is_first_success(tx) -> bool:
    """update_status returns prevStatus, so only the caller that performed the
    pending→succeeded flip sees this as True."""
    return isinstance(tx, dict) and tx.get("status") == "succeeded" and tx.get("prevStatus") != "succeeded"


def _intent_fee_and_net(tx: dict, stripe_account: str = None) -> tuple[float, float]:
    """(feeMXN, netMXN) for a transaction when only its row is at hand (webhook)."""
    intent_id = tx.get("stripePaymentIntentId") or ""
    intent = None
    if intent_id and not intent_id.startswith("pi_mock_"):
        try:
            intent = stripe.PaymentIntent.retrieve(
                intent_id, expand=["latest_charge.balance_transaction"],
                **({"stripe_account": stripe_account} if stripe_account else {}))
        except Exception as e:
            print(f"[stripe][topup] intent retrieve for net FAILED: {e}")
    return _stripe_fee_and_net_mxn(intent, float(tx.get("amount", 0)) / 100.0)


def _send_receipt_async(tx: dict, intent_id: str, fee_mxn: float, net_mxn: float) -> None:
    """Comprobante por correo en un hilo aparte — no retrasa la respuesta."""
    threading.Thread(target=_send_transaction_receipt_email,
                     args=(tx, intent_id, fee_mxn, net_mxn), daemon=True).start()


async def _settle_wallet_top_up(tx: dict, net_mxn: float = None, stripe_account: str = None):
    """Credit the client's wallet ledger for a wallet_top_up / laundry_top_up transaction that
    JUST transitioned to succeeded. Runs from both the app's confirm call and
    the Stripe webhook — sp_stripe_transactions.update_status returns the
    previous status, so only the caller that performed the pending→succeeded
    flip credits; the other sees prevStatus='succeeded' and skips.

    La cartera P2P recibe el NETO real (bruto − comisión Stripe): si el caller
    no lo pasa (webhook), se resuelve aquí desde el balance transaction del
    intent, con la fórmula MX como fallback. El saldo de una compañía recibe el
    BRUTO: la comisión la absorbe la compañía (RFC-012, decisión A)."""
    try:
        if not isinstance(tx, dict) or tx.get("paymentType") not in _TOP_UP_TYPES:
            return
        if tx.get("status") != "succeeded" or tx.get("prevStatus") == "succeeded":
            print(f"[stripe][topup] settle skipped (status={tx.get('status')}, prev={tx.get('prevStatus')})")
            return
        gross_mxn  = float(tx.get("amount", 0)) / 100.0  # stored in centavos
        client_id  = tx.get("fromClientId")
        company_id = tx.get("companyId")
        if not client_id or gross_mxn <= 0:
            return

        if net_mxn is None:
            _fee, net_mxn = _intent_fee_and_net(tx, stripe_account)

        if tx.get("paymentType") == LAUNDRY_TOP_UP:
            intent_id = tx.get("stripePaymentIntentId") or ""
            entry = post_entry(
                company_id=int(company_id), client_id=int(client_id), entry_type="DEPOSIT",
                direction="C", amount_mxn=gross_mxn, idempotency_key=f"stripe:{intent_id}",
                reference_type="stripe_tx", reference_id=tx.get("transactionId"),
                note="Recarga con tarjeta (Stripe)",
            )
            if entry.get("error"):
                raise RuntimeError(entry["error"])
            log_workflow_step("Laundry Balance Credited", workflow_name="money_trail",
                              action=LAUNDRY_TOP_UP, entity="walletTransactions",
                              entity_id=entry.get("entryId"),
                              message=f"+${gross_mxn:,.2f} MXN; comisión ${gross_mxn - net_mxn:,.2f} "
                                      f"a cargo de la compañía — intent {intent_id}")
            print(f"[stripe][topup] laundry balance CREDITED clientId={client_id} +{gross_mxn} MXN "
                  f"(company fee {round(gross_mxn - net_mxn, 2)}, intent {intent_id})")
            return

        from modules.walletBalance import credit_wallet
        await credit_wallet({
            "clientId": client_id, "companyId": company_id,
            "amountMXN": net_mxn, "type": "top_up",
        })
        print(f"[stripe][topup] wallet CREDITED clientId={client_id} +{net_mxn} MXN neto "
              f"(bruto {gross_mxn}, intent {tx.get('stripePaymentIntentId')})")
    except Exception as e:
        # Ledger credit must not fail the confirm/webhook response; the
        # transaction row is already 'succeeded' for reconciliation.
        print(f"[stripe][topup] wallet credit FAILED: {e}")


def _persist_intent_payment_method(intent, tx: dict, company_id):
    """Persist the card used in a succeeded PaymentIntent into
    savedPaymentMethods (checkbox "guardar tarjeta" del frontend) — same table
    /automated-payments/saved-method reads for the auto-charge of cuotas.
    Best-effort: a failure here must never fail the confirm response."""
    try:
        pm_field = intent["payment_method"]
        pm_id = getattr(pm_field, "id", None) or pm_field
        if not pm_id:
            print("[stripe][confirm] save card skipped: intent has no payment_method")
            return
        pm = stripe.PaymentMethod.retrieve(pm_id)
        card = getattr(pm, "card", None)
        if not card:
            # OXXO / non-card methods can't be reused for auto-charges.
            print(f"[stripe][confirm] save card skipped: pm {pm_id} is not a card")
            return
        client_id = tx.get("fromClientId") or getattr(intent["metadata"], "fromClientId", None)
        if not client_id:
            print("[stripe][confirm] save card skipped: no fromClientId on tx/metadata")
            return
        # Import perezoso: automatedPayments importa de este módulo, un import
        # a nivel de módulo crearía un ciclo (mismo patrón que credit_wallet).
        from modules.automatedPayments import _sp_saved_methods
        result = _sp_saved_methods({
            "action": "upsert",
            "clientId": int(client_id),
            "companyId": company_id,
            "stripePaymentMethodId": pm_id,
            "last4":       getattr(card, "last4", ""),
            "brand":       getattr(card, "brand", ""),
            "expiryMonth": getattr(card, "exp_month", None),
            "expiryYear":  getattr(card, "exp_year", None),
        })
        print(f"[stripe][confirm] card SAVED clientId={client_id} pm={pm_id} → {result}")
    except Exception as e:
        print(f"[stripe][confirm] save card FAILED (non-fatal): {type(e).__name__}: {e}")


def _client_contact(client_id) -> dict:
    """Email y nombre del cliente para el comprobante — lectura directa,
    best-effort (un fallo aquí nunca afecta la transacción)."""
    conn = None
    try:
        conn = connection()
        cur = conn.cursor()
        cur.execute("EXEC sp_clients_one @pjsonfile = %s",
                    (json.dumps({"clients": [{"clientId": client_id}]}),))
        # FOR JSON AUTO may split the payload across several rows
        rows = cur.fetchall()
        json_text = "".join((r[0] or "") for r in rows).strip() if rows else ""
        if not json_text:
            return {}
        clients = json.loads(json_text).get("clients") or []
        if not clients:
            return {}
        c = clients[0]
        return {"email": (c.get("email") or "").strip(),
                "name": f"{c.get('first_name') or ''} {c.get('last_name') or ''}".strip() or "cliente"}
    except Exception as e:
        print(f"[stripe][receipt] client lookup FAILED: {e}")
        return {}
    finally:
        if conn:
            conn.close()


def _send_transaction_receipt_email(tx: dict, intent_id: str,
                                    fee_mxn: float, net_mxn: float):
    """Comprobante por correo de cada movimiento (el "ticket" del cliente):
    folio = transactionId, referencia Stripe, montos y comisión — equivalente
    al comprobante bancario. Corre en un hilo aparte y es best-effort: nunca
    retrasa ni rompe la respuesta del confirm. El registro persistente por
    canal (email/push/inapp) con estado pending→sent→confirmed es el módulo
    transactionNotification del factory (PRD ya autorado)."""
    try:
        client_id = tx.get("fromClientId")
        if not client_id:
            return
        contact = _client_contact(client_id)
        email = contact.get("email") or ""
        if "@" not in email:
            print(f"[stripe][receipt] clientId={client_id} sin email — comprobante omitido")
            return
        gross_mxn = float(tx.get("amount", 0)) / 100.0
        folio = tx.get("transactionId") or "—"
        payment_type = tx.get("paymentType") or ""
        concepto = ("Recarga de cartera P2P" if payment_type == "wallet_top_up"
                    else f"Recarga de saldo {company_name({'companyId': tx.get('companyId')})}".strip() if payment_type == LAUNDRY_TOP_UP
                    else "Pago de préstamo" if payment_type == "loan_repayment"
                    else payment_type or "Movimiento")
        fecha = datetime.utcnow().strftime("%d/%m/%Y %H:%M UTC")
        negocio = ((company_name({"companyId": tx.get("companyId")}) if payment_type == LAUNDRY_TOP_UP else "")
                   or "SmartLoans")
        lineas = [
            f"Hola {contact.get('name', 'cliente')},",
            "",
            f"Tu operación en {negocio} fue procesada con éxito.",
            "",
            f"Concepto:            {concepto}",
            f"Folio de operación:  {folio}",
            f"Referencia Stripe:   {intent_id}",
            f"Fecha y hora:        {fecha}",
            "",
            f"Monto pagado:        ${gross_mxn:,.2f} MXN",
        ]
        if payment_type == LAUNDRY_TOP_UP:
            # The company absorbs the fee: the client is credited what they paid.
            lineas.append(f"Abonado a tu saldo:   ${gross_mxn:,.2f} MXN")
        else:
            lineas.append(f"Comisión Stripe:     -${fee_mxn:,.2f} MXN")
            if payment_type == "wallet_top_up":
                lineas.append(f"Abonado a tu cartera: ${net_mxn:,.2f} MXN")
        lineas += [
            "",
            "Puedes consultar este movimiento en la app GMO → SmartLoans → Movimientos.",
            "",
            "— SmartLoans · GMO",
            "Este correo es el comprobante informativo de tu transacción.",
        ]
        subject = f"Comprobante SmartLoans — {concepto} ${gross_mxn:,.2f} MXN (folio {folio})"
        # Import perezoso para no acoplar módulos al cargar.
        from modules.users import _send_email
        _send_email(email, subject, "\n".join(lineas))
        print(f"[stripe][receipt] comprobante ENVIADO a {email} folio={folio}")
    except Exception as e:
        print(f"[stripe][receipt] email FAILED (non-fatal): {type(e).__name__}: {e}")


async def confirm_payment_intent(payload: dict):
    """
    Verify a PaymentIntent succeeded (called by frontend after confirmation).
    Updates SQL transaction status to 'succeeded' and, for wallet top-ups,
    credits the client's wallet ledger exactly once. With savePaymentMethod
    (checkbox del frontend) also persists the card to savedPaymentMethods.
    Envía además el comprobante por correo (folio + referencia + comisión).
    """
    payment_intent_id = payload.get("paymentIntentId")
    company_id        = payload.get("companyId")
    save_pm           = bool(payload.get("savePaymentMethod"))

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
            mock_gross = float(tx.get("amount", 0)) / 100.0
            mock_fee, mock_net = _stripe_fee_and_net_mxn(None, mock_gross)
            await _settle_wallet_top_up(tx, net_mxn=mock_net)
            if save_pm and tx.get("fromClientId"):
                # Mock card, same shape save_payment_method uses in dev.
                from modules.automatedPayments import _sp_saved_methods
                _sp_saved_methods({
                    "action": "upsert",
                    "clientId": tx.get("fromClientId"),
                    "companyId": company_id,
                    "stripePaymentMethodId": "pm_mock_card",
                    "last4": "4242", "brand": "visa",
                    "expiryMonth": 12, "expiryYear": 2030,
                })
            return JSONResponse({"status": "succeeded", "stripePaymentIntentId": payment_intent_id,
                                 "feeMXN": mock_fee, "netCreditedMXN": _credited_mxn(tx, mock_gross, mock_net),
                                 **tx}, status_code=200)

        # expand: el balance transaction trae la comisión REAL de Stripe para
        # acreditar la cartera con el neto y reportarla al cliente.
        # A company top-up lives on that company's Stripe account, not the platform's.
        connected_account = (_intent_account(company_id, payload.get("stripeAccount"))
                             if payload.get("paymentType") == LAUNDRY_TOP_UP else None)
        intent = stripe.PaymentIntent.retrieve(
            payment_intent_id, expand=["latest_charge.balance_transaction"],
            **_on(connected_account))
        # Bracket access, not .get(): stripe 15.x StripeObject is no longer a
        # dict — .get() raises AttributeError and this endpoint 500'd on every
        # call (same bug automatedPayments already fixed).
        status = intent["status"]

        tx = _sp_transaction({
            "action": "update_status",
            "stripePaymentIntentId": payment_intent_id,
            "status": status,
            "companyId": company_id,
        })

        log_integration("stripe", "payment_intent_retrieve",
                        response={"paymentIntentId": payment_intent_id, "status": status})

        if status != "succeeded":
            log_workflow_step("Charge Confirm Rejected", workflow_name="money_trail", status="FAILED",
                              entity="stripeTransactions", entity_id=tx.get("transactionId"),
                              message=f"intent {payment_intent_id} status={status}")
            return JSONResponse({"error": f"Payment status: {status}"}, status_code=400)

        gross_mxn = float(intent["amount"]) / 100.0
        fee_mxn, net_mxn = _stripe_fee_and_net_mxn(intent, gross_mxn)
        log_workflow_step("Charge Confirmed", workflow_name="money_trail",
                          action=tx.get("paymentType") or "charge",
                          entity="stripeTransactions", entity_id=tx.get("transactionId"),
                          message=f"bruto ${gross_mxn:,.2f} − comisión ${fee_mxn:,.2f} = neto ${net_mxn:,.2f} MXN")
        first_success = _is_first_success(tx)
        await _settle_wallet_top_up(tx, net_mxn=net_mxn)

        if save_pm:
            _persist_intent_payment_method(intent, tx, company_id)

        if first_success:
            _send_receipt_async(tx, payment_intent_id, fee_mxn, net_mxn)

        return JSONResponse({"status": status, "stripePaymentIntentId": payment_intent_id,
                             "feeMXN": fee_mxn, "netCreditedMXN": _credited_mxn(tx, gross_mxn, net_mxn),
                             **tx}, status_code=200)

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

        log_integration("stripe", "transfer_create",
                        response={"transferId": transfer["id"], "amountMXN": amount_mxn})
        log_workflow_step("Loan Disbursed via Stripe", workflow_name="money_trail", action="loan_disbursement",
                          entity="loans", entity_id=loan_id,
                          message=f"${amount_mxn:,.2f} MXN lender {lender_id} → borrower {borrower_id} (transfer {transfer['id']})")

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
            log_integration("stripe", "payout_create",
                            response={"payoutId": payout_id, "amountMXN": amount_mxn})

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

        log_workflow_step("Withdrawal Payout", workflow_name="money_trail", action="wallet_withdrawal",
                          entity="stripeTransactions", entity_id=tx.get("transactionId"),
                          message=f"${amount_mxn:,.2f} MXN → banco externo de clientId {client_id} (payout {payout_id})")

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

    secrets = [s for s in (WEBHOOK_SECRET, CONNECT_WEBHOOK_SECRET) if s and not s.startswith("whsec_YOUR")]
    if not secrets:
        # Webhook secret not configured — parse without verification (dev only)
        event = json.loads(payload_bytes)
        if event.get("account") or "_live_" in (stripe.api_key or ""):
            # Never credit real money from an event nobody verified.
            print("[stripe][webhook] rejected: no webhook secret configured")
            return JSONResponse({"error": "Webhook secret not configured"}, status_code=400)
    else:
        event = None
        for secret in secrets:
            try:
                # construct_event VERIFIES the signature but returns a stripe 15.x
                # StripeObject, which no longer supports dict .get() — every
                # handler below crashed with AttributeError('get') and Stripe saw
                # nothing but 500s. Verify with it, then work on the plain-JSON
                # payload so the .get() handling keeps working in any SDK version.
                stripe.Webhook.construct_event(payload_bytes, sig_header, secret)
                event = json.loads(payload_bytes)
                break
            except stripe.SignatureVerificationError as e:
                print(f"[stripe][webhook] Signature verification failed: {e}")
        if event is None:
            return JSONResponse({"error": "Invalid signature"}, status_code=400)

    event_type = event.get("type", "")
    data_obj   = event.get("data", {}).get("object", {})
    connected_account = event.get("account")

    # A company's Stripe account also has its own sales; only our top-ups matter.
    if (connected_account and event_type.startswith("payment_intent.")
            and (data_obj.get("metadata") or {}).get("paymentType") != LAUNDRY_TOP_UP):
        return JSONResponse({"received": True}, status_code=200)

    print(f"[stripe][webhook] Received event: {event_type}")

    if event_type == "payment_intent.succeeded":
        intent_id = data_obj.get("id")
        metadata  = data_obj.get("metadata", {})

        # Compra de FICHAS del arcade: no es dinero del usuario sino ingreso
        # por un bien virtual, asi que no tiene fila en stripeTransactions ni
        # toca el ledger de la billetera. Se acredita aparte y se corta aqui.
        #
        # Este camino existe para cuando el navegador se cierra justo despues
        # de pagar: sin webhook el usuario quedaria cobrado y sin fichas. Si la
        # pestana si alcanzo a confirmar, el indice unico de arcadePurchases
        # hace que este segundo intento no acredite de nuevo.
        if metadata.get("kind") == "arcade_chips":
            from modules.arcadeStore import credit_stripe_chip_purchase
            result = credit_stripe_chip_purchase(data_obj)
            log_workflow_step("Webhook Chip Purchase", workflow_name="arcade_store",
                              entity="arcadePurchases",
                              message=f"intent {intent_id} -> {result.get('status') or result.get('error')}")
            print(f"[stripe][webhook] Arcade chips: {intent_id} -> {result.get('status') or result.get('error')}")
            return JSONResponse({"received": True}, status_code=200)

        tx = _sp_transaction({
            "action": "update_status",
            "stripePaymentIntentId": intent_id,
            "status": "succeeded",
            "companyId": metadata.get("companyId"),
        })
        # Wallet top-ups: credit the ledger (no-op if the app's confirm call
        # already did — update_status returns prevStatus for idempotency).
        if _is_first_success(tx):
            fee_mxn, net_mxn = _intent_fee_and_net(tx, connected_account)
            await _settle_wallet_top_up(tx, net_mxn=net_mxn)
            _send_receipt_async(tx, intent_id, fee_mxn, net_mxn)
        log_workflow_step("Webhook Payment Succeeded", workflow_name="money_trail",
                          entity="stripeTransactions",
                          entity_id=tx.get("transactionId") if isinstance(tx, dict) else None,
                          message=f"intent {intent_id}")
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
        elif company_id:
            sync_charges_enabled({"stripeConnectedAccountId": acct_id, "chargesEnabled": charges_enabled})
        print(f"[stripe][webhook] Account updated: {acct_id} charges={charges_enabled}")

    return JSONResponse({"received": True}, status_code=200)
