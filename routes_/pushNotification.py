from fastapi import APIRouter
from modules.pushNotifications import pushNotifications_sp, all_pushNotifications_sp, one_pushNotifications_sp


router = APIRouter()

with open("./docs_description/pushNotifications.txt", "r") as file:
    pushNotifications_docstring = file.read()
@router.post("/pushNotifications", summary="pushNotifications CRUD", description=pushNotifications_docstring)
def pushNotifications(json: dict):
    return pushNotifications_sp(json)


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
