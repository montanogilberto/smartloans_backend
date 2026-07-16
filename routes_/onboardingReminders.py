from fastapi import APIRouter
from modules.onboardingReminders import check_onboarding_completeness

router = APIRouter(prefix="/onboarding-reminders", tags=["Onboarding Reminders"])


@router.post(
    "/check",
    summary="Scan all clients for incomplete onboarding and send one-time reminders",
    description="""
Checks Código QR, ID document capture, biometric verification, contract/pagaré
acceptance, and payment account setup (bank account + saved card) for every
client in the company. sp_onboardingReminders' 'getIncomplete' action already
excludes clients previously reminded, so this only ever processes clients
not yet marked. Sends one consolidated push notification per incomplete
client, then marks them via the same SP's 'markReminded' action so each
client is only ever reminded once automatically (staff can still manually
nudge a client through the wizard at any time).

Set dryRun=true to preview who would be reminded without sending anything
or marking them as reminded. Recommended: call daily from a scheduled
trigger, same as /automated-payments/charge-due.

Body: { "companyId": int, "dryRun"?: bool }
Returns: { dryRun, reminded, complete, total, details: [{ clientId, missing }] }
""",
)
async def check(json: dict):
    return await check_onboarding_completeness(json)
