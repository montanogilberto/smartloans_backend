from fastapi import APIRouter
from modules.IOT import led_status_sp, tankWaters_sp, all_tankWaters_sp

router = APIRouter()

# Read all laundry docstring from the file
with open("./docs_description/led_status.txt", "r") as file:
    led_status_docstring = file.read()
@router.post("/led_status", summary="led status", description=led_status_docstring)
def led_status(json: dict):
    return led_status_sp(json)


# Read all tankWaters docstring from the file
with open("./docs_description/tankWaters_all.txt", "r") as file:
    tankWaters_all_docstring = file.read()
@router.get("/all_tankWaters",  summary="all tankWaters", description=tankWaters_all_docstring)
def all_tankWaters():
    return  all_tankWaters_sp()

# Read checks  docstring from the file
with open("./docs_description/tankWaters.txt", "r") as file:
    tankWaters_docstring = file.read()
@router.post("/tankWaters",  summary="tankWaters CRUD", description=tankWaters_docstring)
def tankWaters(json: dict):
    return  tankWaters_sp(json)