from fastapi import APIRouter
from modules.rewards import rewards_sp

router = APIRouter()

@router.post("/rewards", summary="Rewards & Loyalty Points CRUD",
    description="""
actions:
  upsert_rule   — create or update a reward rule
  delete_rule   — soft-delete a rule (isActive=0)
  list_rules    — all active rules for a company
  earn          — add points to a client (after a sale/service)
  redeem        — subtract points (client uses them)
  get_balance   — current balance + lifetime stats for a client
  list_transactions — last 50 transactions (company or client)
  list_balances — all client balances for a company (leaderboard)

Body always: { "rewards": [{ "action": "...", "companyId": int, ...fields }] }
""")
def rewards(json: dict):
    payload = json.get("rewards", [{}])[0]
    return rewards_sp(payload)
