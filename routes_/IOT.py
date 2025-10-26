from fastapi import APIRouter
from modules.IOT import led_status_sp

router = APIRouter()

# Read all laundry docstring from the file
with open("./docs_description/led_status.txt", "r") as file:
    led_status_docstring = file.read()
@router.post("/led_status", summary="led status", description=led_status_docstring)
def led_status(json: dict):
    return led_status_sp(json)