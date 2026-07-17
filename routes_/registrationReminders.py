from fastapi import APIRouter
from modules.registrationReminders import check_registration_completeness

router = APIRouter(prefix="/registration-reminders", tags=["Registration Reminders"])


@router.post(
    "/check",
    summary="Scan all users for incomplete registration and send one-time reminders",
    description="""
Checks the CreateAccount.tsx wizard's Perfil, Verificar and Acceso steps for
every user in dbo.users. sp_registrationReminders' 'getIncomplete' action
already excludes users previously reminded, so this only ever processes
users not yet marked. Sends email (if available) plus the first of
push / WhatsApp / SMS that actually delivers, then marks the user via the
same SP's 'markReminded' action so each user is only ever reminded once
automatically.

Set dryRun=true to preview who would be reminded without sending anything
or marking them as reminded. Recommended: call daily from a scheduled
trigger, same as /onboarding-reminders/check.

Body: { "dryRun"?: bool }
Returns: { dryRun, reminded, total, details: [{ userId, missing, channel }] }
""",
)
async def check(json: dict):
    return await check_registration_completeness(json)
