from fastapi import APIRouter
from modules.notificationAudiences import notificationAudiences_sp

router = APIRouter()


@router.post(
    "/notificationAudiences",
    summary="Notification Audience — action routing",
    description="""
actions:
  upsert  — Upsert the audience of one notification. Called internally by modules/pushNotifications.py right after sp_pushNotifications creates the row; also usable by staff tooling.

Body: { "notificationAudiences": [{ "action": "...", "companyId": int, ...action fields }] }
"""
)
async def notificationAudiences(json: dict):
    payload = json.get("notificationAudiences", [{}])[0] if isinstance(json.get("notificationAudiences"), list) else json
    return await notificationAudiences_sp(payload)
