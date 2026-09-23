from fastapi import APIRouter
from modules.transactionNotifications import (
    transactionNotifications_sp,
    all_transactionNotifications_sp,
    one_transactionNotifications_sp,
    dispatch_transactionNotification_connector,
    confirm_transactionNotification_connector,
)


router = APIRouter()

with open("./docs_description/transactionNotifications.txt", "r") as file:
    transactionNotifications_docstring = file.read()
@router.post("/transactionNotifications", summary="transactionNotifications CRUD", description=transactionNotifications_docstring)
def transactionNotifications(json: dict):
    return transactionNotifications_sp(json)


with open("./docs_description/transactionNotifications_all.txt", "r") as file:
    transactionNotifications_all_docstring = file.read()
@router.post("/all_transactionNotifications", summary="all transactionNotifications", description=transactionNotifications_all_docstring)
def all_transactionNotifications(json: dict):
    return all_transactionNotifications_sp(json)


with open("./docs_description/transactionNotifications_one.txt", "r") as file:
    transactionNotifications_one_docstring = file.read()
@router.post("/one_transactionNotification", summary="one transactionNotification", description=transactionNotifications_one_docstring)
def one_transactionNotification(json: dict):
    return one_transactionNotifications_sp(json)


# --- Connector Routes ---

@router.post("/transactionNotifications/dispatch", summary="Dispatch Transaction Notifications", tags=["connector"])
async def dispatch_transactionNotifications_route(json: dict):
    return await dispatch_transactionNotification_connector(json)


@router.post("/transactionNotifications/confirm", summary="Confirm Transaction Notifications via Webhook", tags=["connector"])
async def confirm_transactionNotifications_route(json: dict):
    return await confirm_transactionNotification_connector(json)
