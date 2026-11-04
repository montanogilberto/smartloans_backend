from fastapi import APIRouter, Depends
from security.rate_limit import field, rate_limit
from modules.notificationDispatch import (
    notificationDispatch_sp,
    all_notificationDispatch_sp,
    one_notificationDispatch_sp,
    dispatch_notification_connector,
    confirm_notification_connector,
)

router = APIRouter()


@router.post("/notificationDispatches", summary="notificationDispatch CRUD")
def notificationDispatches(json: dict):
    return notificationDispatch_sp(json)


@router.post("/all_notificationDispatches", summary="all notificationDispatches")
def all_notificationDispatches(json: dict):
    return all_notificationDispatch_sp(json)


@router.post("/one_notificationDispatches", summary="one notificationDispatch")
def one_notificationDispatches(json: dict):
    return one_notificationDispatch_sp(json)


@router.post(
    "/notificationDispatch/dispatch",
    dependencies=[Depends(rate_limit("dispatch", per_ip=600, per_target=20, window=3600,
                                     target=field("phone")))],
    summary="Push -> WhatsApp -> SMS cost-minimizing notification cascade",
    tags=["connector"],
)
async def notification_dispatch(json: dict):
    return await dispatch_notification_connector(json)


@router.post(
    "/notificationDispatch/confirm",
    summary="Confirm/fail a dispatched notification by providerMessageId",
    tags=["connector"],
)
async def notification_confirm(json: dict):
    return await confirm_notification_connector(json)
