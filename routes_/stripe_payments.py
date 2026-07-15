from fastapi import APIRouter, Request
from modules.stripe_payments import (
    create_connected_account,
    get_connected_account_status,
    create_account_session,
    get_onboarding_link,
    create_payment_intent,
    confirm_payment_intent,
    disburse_loan,
    list_transactions,
    handle_webhook,
)

router = APIRouter(prefix="/stripe", tags=["Stripe Connect"])


# ── Connected Accounts (KYC) ─────────────────────────────────────────────────

@router.post(
    "/connected-accounts",
    summary="Create or retrieve a Stripe Express Connected Account for a client",
    description="""
Creates a Stripe Express account for KYC/charges if one does not yet exist.
If the client already has an account, refreshes and returns the current status.

Body: { "clientId": int, "companyId": int, "email": str }
Returns: { "account": { connectedAccountId, chargesEnabled, payoutsEnabled, detailsSubmitted } }
""",
)
async def create_or_get_connected_account(json: dict):
    return await create_connected_account(json)


@router.post(
    "/connected-accounts/status",
    summary="Get KYC/charges status for a client's Stripe Connected Account",
    description="""
Returns the live Stripe account status (charges_enabled, payouts_enabled, details_submitted).

Body: { "clientId": int, "companyId": int }
Returns: { "account": ConnectedAccount | null }
""",
)
async def connected_account_status(json: dict):
    return await get_connected_account_status(json)


@router.post(
    "/account-session",
    summary="Create a Stripe Account Session for embedded onboarding",
    description="""
Returns a client_secret used to initialize Stripe Connect embedded components
(@stripe/connect-js) so the client completes KYC (ID, selfie, CLABE) inside
the app itself instead of an external browser redirect.

Body: { "clientId": int, "companyId": int }
Returns: { "clientSecret": str }
""",
)
async def account_session(json: dict):
    return await create_account_session(json)


@router.post(
    "/onboarding-link",
    summary="Generate a Stripe Express onboarding URL for KYC",
    description="""
Returns a short-lived Stripe onboarding URL. Open in browser/webview so the client
can submit their ID (INE/passport), selfie, and CLABE for payouts.

Body: { "clientId": int, "companyId": int, "returnUrl": str, "refreshUrl": str }
Returns: { "url": str, "expiresAt": unix_timestamp }
""",
)
async def onboarding_link(json: dict):
    return await get_onboarding_link(json)


# ── Payment Intents ───────────────────────────────────────────────────────────

@router.post(
    "/payment-intents",
    summary="Create a Stripe PaymentIntent (wallet top-up or loan repayment)",
    description="""
Backend creates the PaymentIntent with your Stripe secret key and returns only
the client_secret to the frontend. The card number never passes through your servers.

paymentType values: wallet_top_up | loan_disbursement | loan_repayment | wallet_withdrawal

Body: {
  "companyId": int, "fromClientId": int, "toClientId": int,
  "amount": int (centavos MXN),  "paymentType": str,
  "loanId"?: int, "proposalId"?: int, "description"?: str
}
Returns: { "clientSecret": str, "paymentIntentId": str, "transactionId": int, "amount": int, "currency": "mxn" }
""",
)
async def payment_intent(json: dict):
    return await create_payment_intent(json)


@router.post(
    "/payment-intents/confirm",
    summary="Verify a PaymentIntent succeeded and update SQL transaction status",
    description="""
Called by the frontend after stripe.confirmPayment() resolves without error.
Retrieves the PaymentIntent from Stripe server-side to verify its status
and updates the local transaction record.

Body: { "paymentIntentId": str, "companyId": int }
Returns: { "status": str, "stripePaymentIntentId": str, ...transactionFields }
""",
)
async def confirm_intent(json: dict):
    return await confirm_payment_intent(json)


# ── Loan Disbursement ─────────────────────────────────────────────────────────

@router.post(
    "/disburse",
    summary="Transfer loan funds from platform to borrower's Connected Account",
    description="""
Called automatically when a lender accepts a borrower's proposal.
Transfers from the platform Stripe account to the borrower's Express account,
from where Stripe pays out to the borrower's CLABE.

Body: {
  "companyId": int, "loanId": int, "proposalId": int,
  "lenderId": int, "borrowerId": int, "amount": float (MXN)
}
Returns: { "status": str, "transactionId": int, "stripeTransferId": str }
""",
)
async def disburse(json: dict):
    return await disburse_loan(json)


# ── Transactions ──────────────────────────────────────────────────────────────

@router.post(
    "/transactions",
    summary="List Stripe payment transactions",
    description="""
Returns payment transaction history for a company/client/loan.

Body: { "companyId": int, "clientId"?: int, "loanId"?: int, "paymentType"?: str }
Returns: { "transactions": PaymentTransaction[] }
""",
)
async def transactions(json: dict):
    return await list_transactions(json)


# ── Webhook ───────────────────────────────────────────────────────────────────

@router.post(
    "/webhook",
    summary="Stripe webhook receiver",
    description="""
Register this endpoint in the Stripe Dashboard under Developers → Webhooks.
URL: https://smartloansbackend.azurewebsites.net/stripe/webhook

Listens for:
  - payment_intent.succeeded
  - payment_intent.payment_failed
  - account.updated
  - transfer.created

Validates the Stripe-Signature header using STRIPE_WEBHOOK_SECRET env var.
""",
)
async def webhook(request: Request):
    return await handle_webhook(request)
