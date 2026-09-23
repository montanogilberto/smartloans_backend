from fastapi import APIRouter
from fastapi.responses import JSONResponse
from modules.reservations import reservations_sp, run_migration

router = APIRouter()


@router.post(
    "/reservations",
    summary="Laundry service reservations CRUD",
    description="""
action 0 (or omit) — read/list:
  { "reservations": [{ "companyId": int, "reservationId"?: int,
    "date"?: "YYYY-MM-DD", "status"?: "pending|confirmed|cancelled|completed" }] }

action 1 — create (kiosk):
  { "reservations": [{ "action": 1, "companyId": int, "clientName": str,
    "phone": str (E.164), "email"?: str, "serviceType": "lavado|secado",
    "serviceDetail"?: str, "reservationDate": "YYYY-MM-DD",
    "timeSlot": "HH:MM", "notes"?: str }] }
  → sends SMS + WhatsApp + email confirmation to customer

action 2 — confirm (POS staff):
  { "reservations": [{ "action": 2, "reservationId": int, "companyId": int,
    "confirmedByUserId"?: int }] }

action 3 — cancel:
  { "reservations": [{ "action": 3, "reservationId": int, "companyId": int }] }

action 4 — complete:
  { "reservations": [{ "action": 4, "reservationId": int, "companyId": int }] }

action 5 — list pending+confirmed for POS queue (today onward):
  { "reservations": [{ "action": 5, "companyId": int }] }
""",
)
def reservations(json: dict):
    return reservations_sp(json)


@router.post(
    "/reservations/migrate",
    summary="Create reservations table + SP on the database (idempotent)",
)
def reservations_migrate():
    try:
        result = run_migration()
        return JSONResponse(result, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
