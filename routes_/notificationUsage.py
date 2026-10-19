from fastapi import APIRouter

from modules.notificationUsage import notification_usage

router = APIRouter()


@router.get(
    "/notifications/usage",
    summary="Notification usage this month that only the providers know (Twilio counts + WhatsApp settings)",
    description="""
Returns: { ok: true, period: "this_month", since: ISO-UTC (Hermosillo month start),
           whatsappProvider: "meta" | "none",
           whatsappLimit: int | null,
           twilio: { ok: true,
                     whatsapp: { delivered, failed, inFlight, total },
                     sms:      { delivered, failed, inFlight, total } }
                 | { ok: false, error } }

Read-only; cached 60 s (a Twilio failure is not cached). Twilio numbers are the
whole Twilio account (every company and direct ticket sends), counted from the
Messages API by final status — not Usage Records, which skip unpriced messages.
Meta WhatsApp and Push are not here: the screen counts them from
dbo.notificationDispatches (Meta status webhooks set confirmed/failed; Notification
Hub has no per-device receipt). whatsappLimit is WHATSAPP_FREE_MONTHLY_LIMIT.
""",
)
def notifications_usage():
    return notification_usage()
