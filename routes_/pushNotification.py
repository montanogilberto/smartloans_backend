from fastapi import APIRouter, Depends
from security.worker_key import require_worker_key
from modules.pushNotifications import (
    pushNotifications_sp,
    all_pushNotifications_sp,
    one_pushNotifications_sp,
    register_device_sp,
    my_notifications_sp,
    mark_notifications_read_sp,
)


router = APIRouter()

with open("./docs_description/pushNotifications.txt", "r") as file:
    pushNotifications_docstring = file.read()
@router.post("/pushNotifications", summary="pushNotifications CRUD", description=pushNotifications_docstring)
async def pushNotifications(json: dict):
    print("[pushNotifications][route] Incoming request payload:", json)
    response = await pushNotifications_sp(json)
    print("[pushNotifications][route] Outgoing response prepared.")
    return response


with open("./docs_description/pushNotifications_all.txt", "r") as file:
    pushNotifications_all_docstring = file.read()
@router.post("/all_pushNotifications", summary="all pushNotifications", description=pushNotifications_all_docstring)
def all_pushNotifications(json: dict):
    return all_pushNotifications_sp(json)


with open("./docs_description/pushNotifications_one.txt", "r") as file:
    pushNotifications_one_docstring = file.read()
@router.post("/one_pushNotification", summary="one pushNotification", description=pushNotifications_one_docstring)
def one_pushNotification(json: dict):
    return one_pushNotifications_sp(json)


with open("./docs_description/registerDevice.txt", "r") as file:
    register_device_docstring = file.read()
@router.post("/registerDevice", summary="register device token", description=register_device_docstring,
             dependencies=[Depends(require_worker_key)])
async def registerDevice(json: dict):
    print("[pushNotifications][route][registerDevice] Incoming request payload:", json)
    response = await register_device_sp(json)
    print("[pushNotifications][route][registerDevice] Outgoing response prepared.")
    return response


@router.post(
    "/myNotifications",
    summary="Per-user notification inbox (bell icon)",
    description="""Body: { "userId": int }
Returns: { unreadCount, notifications: [{ pushNotificationId, title, message,
notificationType, priority, navigationRoute, isRead, receivedAt }] } — newest
first, top 50. Backed by NotificationDeliveries so the in-app history persists
after the system push disappears.""",
)
def my_notifications(json: dict):
    return my_notifications_sp(json)


@router.post(
    "/myNotifications/markRead",
    summary="Mark a user's notifications as read",
    description="""Body: { "userId": int, "pushNotificationId"?: int } — omit
pushNotificationId to mark ALL of the user's notifications read.""",
)
def my_notifications_mark_read(json: dict):
    return mark_notifications_read_sp(json)
