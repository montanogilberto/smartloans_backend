from fastapi import APIRouter
from modules.rewards import rewards_sp

router = APIRouter()

# Read rewards docstring from the file
with open("./docs_description/rewards.txt", "r") as file:
    rewards_docstring = file.read()
@router.post("/rewards", summary="Rewards & Loyalty Points CRUD", description=rewards_docstring)
def rewards(json: dict):
    payload = json.get("rewards", [{}])[0]
    return rewards_sp(payload)
