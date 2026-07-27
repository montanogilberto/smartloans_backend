from fastapi import APIRouter
from modules.clientFollowUps import (
    client_followups_sp, all_client_followups_sp, one_client_followup_sp
)

router = APIRouter()


@router.post(
    "/clientFollowUps",
    summary="Client Follow-Ups CRUD",
    description="""
Create, update, or delete a client monitoring / collections follow-up.

action 1 — create:
  { "clientFollowUps": [{ "action": 1, "clientId": int, "companyId": int,
    "riskStatus": "on_track|at_risk|default", "reason"?: str, "note"?: str,
    "assignedTo"?: int, "dueDate"?: str }] }

action 2 — update (change risk / resolve / reassign):
  { "clientFollowUps": [{ "action": 2, "followUpId": int, "riskStatus"?: str,
    "note"?: str, "resolvedAt"?: str }] }

action 3 — delete:
  { "clientFollowUps": [{ "action": 3, "followUpId": int }] }
""",
)
def client_followups(json: dict):
    return client_followups_sp(json)


@router.post(
    "/all_clientFollowUps",
    summary="List all Client Follow-Ups",
    description="""
Returns all follow-ups for a company, optionally filtered by clientId or riskStatus.

Body: { "clientFollowUps": [{ "companyId": int, "clientId"?: int, "riskStatus"?: str }] }
Returns: { "clientFollowUps": ClientFollowUp[] }
""",
)
def all_client_followups(json: dict):
    return all_client_followups_sp(json)


@router.post(
    "/one_clientFollowUp",
    summary="Get one Client Follow-Up",
    description="""
Returns a single follow-up by followUpId.

Body: { "clientFollowUps": [{ "followUpId": int }] }
Returns: { "clientFollowUps": [ClientFollowUp] }
""",
)
def one_client_followup(json: dict):
    return one_client_followup_sp(json)
