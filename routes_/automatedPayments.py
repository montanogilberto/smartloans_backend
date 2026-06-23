from fastapi import APIRouter
from modules.automatedPayments import (
    create_setup_intent,
    save_payment_method,
    get_saved_method,
    generate_installment_schedule,
    get_installment_schedule,
    charge_due_installments,
)

router = APIRouter(prefix="/automated-payments", tags=["Automated Payments"])


@router.post(
    "/setup-intent",
    summary="Create a Stripe SetupIntent to save a card for future auto-charges",
    description="""
Step 1 of card-saving flow. Returns a clientSecret that the frontend passes to
Stripe.js confirmSetup(). After confirmation, call /save-method.

Body: { "clientId": int, "companyId": int }
Returns: { "clientSecret": str, "setupIntentId": str }
""",
)
async def setup_intent(json: dict):
    return await create_setup_intent(json)


@router.post(
    "/save-method",
    summary="Save the payment method after SetupIntent confirmed",
    description="""
Step 2 of card-saving flow. Retrieves the confirmed SetupIntent from Stripe,
extracts payment method details, and persists to savedPaymentMethods table.

Body: { "clientId": int, "companyId": int, "setupIntentId": str }
Returns: { "paymentMethod": { last4, brand, expiryMonth, expiryYear } }
""",
)
async def save_method(json: dict):
    return await save_payment_method(json)


@router.post(
    "/saved-method",
    summary="Get saved payment method for a client",
    description="""
Body: { "clientId": int, "companyId": int }
Returns: { "paymentMethod": { last4, brand, expiryMonth, expiryYear } | null }
""",
)
async def saved_method(json: dict):
    return await get_saved_method(json)


@router.post(
    "/generate-schedule",
    summary="Generate amortization schedule for a loan",
    description="""
Creates one loanInstallments row per payment period using French amortization.
Call this immediately after a loan is created (proposal accepted).

Body: {
  "loanId": int, "clientId": int, "companyId": int, "lenderId": int,
  "principalAmount": float, "interestRate": float (annual %),
  "termMonths": int, "disbursementDate": str (ISO 8601)
}
Returns: { monthlyPayment, totalRepayment, totalInterest, installments: [...] }
""",
)
async def generate_schedule(json: dict):
    return await generate_installment_schedule(json)


@router.post(
    "/schedule",
    summary="Get installment schedule for a loan",
    description="""
Body: { "loanId": int, "companyId": int }
Returns: { "installments": [{ installmentNumber, dueDate, amount, principal,
            interest, remainingBalance, status, paidAt }] }
""",
)
async def schedule(json: dict):
    return await get_installment_schedule(json)


@router.post(
    "/charge-due",
    summary="Auto-charge all due installments (cron job trigger)",
    description="""
Finds all loanInstallments with dueDate <= today and status=pending,
then charges the borrower's saved card off-session via Stripe.

Set dryRun=true to preview without charging.

Recommended: call daily from Azure Functions or a cron trigger.

Body: { "companyId": int, "dryRun"?: bool }
Returns: { charged, failed, skipped, total, details: [...] }
""",
)
async def charge_due(json: dict):
    return await charge_due_installments(json)
