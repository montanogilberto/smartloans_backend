from fastapi import APIRouter

from modules.notificationUsage import notification_usage

router = APIRouter()


@router.get(
    "/notifications/usage",
    summary="WhatsApp / SMS usage this month, as reported by the provider",
    description="""
Returns: { ok, source: "twilio", period: "this_month",
           whatsapp: { outboundMessages, inboundMessages, conversations,
                       freeConversations, billableConversations, price, priceUnit,
                       limit|null, remaining|null },
           sms: { outboundMessages } }
or { ok: false, error } when the provider can't be reached.

Read-only; cached 60 s. limit/remaining are only present when
WHATSAPP_FREE_MONTHLY_LIMIT is configured. Counts come from Twilio's usage
records, so messages the provider rejected are NOT counted (unlike
dbo.notificationDispatches, which records acceptance). Messages sent directly
through Meta's Cloud API are not included.
""",
)
def notifications_usage():
    return notification_usage()
