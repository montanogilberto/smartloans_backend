from fastapi import APIRouter, Depends, BackgroundTasks
from security.session_tokens import require_company_admin_on_write
from security.worker_key import require_worker_key
from fastapi.responses import JSONResponse
from modules.reservations import reservation_catalog_sp, reservations_sp, run_migration

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
    "phone": str (E.164), "email"?: str, "reservationServiceId": int,
    "serviceDetail"?: str, "reservationDate": "YYYY-MM-DD",
    "timeSlot": "HH:MM", "notes"?: str }] }
  → sends SMS + WhatsApp + email confirmation to customer, push to POS
  → {"error":"slot_taken"|"past_slot"|"unknown_service"}
  (legacy: "serviceType": <catalog name> instead of reservationServiceId)

action 2 — confirm (POS staff):
  { "reservations": [{ "action": 2, "reservationId": int, "companyId": int,
    "confirmedByUserId"?: int }] }

action 3 — cancel:
  { "reservations": [{ "action": 3, "reservationId": int, "companyId": int }] }

action 4 — complete:
  { "reservations": [{ "action": 4, "reservationId": int, "companyId": int }] }

action 5 — list pending+confirmed for POS queue (today onward):
  { "reservations": [{ "action": 5, "companyId": int }] }

action 6 — free slots for a date (kiosk / WhatsApp calendar):
  { "reservations": [{ "action": 6, "companyId": int, "date": "YYYY-MM-DD",
    "reservationServiceId": int }] }
  → { "result": [{ "date", "reservationServiceId", "serviceName",
      "durationMinutes", "capacity", "open", "close",
      "slots": [{ "timeSlot": "HH:MM", "available": int }] }] }
  Hours from /reservationHours, replaced on a holiday by /reservationHolidays
  (closed day: open/close null, no slots). Action 1 on a closed holiday, or
  outside its special hours → {"error":"closed_day"}.
  Duration/capacity from the service, else its machineType's machines.
""",
)
def reservations(json: dict, background_tasks: BackgroundTasks):
    return reservations_sp(json, background_tasks)


@router.post(
    "/reservationServices",
    summary="Catalog of bookable services (per company)",
    description="""
action 0 (or omit) — list active: { "reservationServices": [{ "companyId": int,
  "includeInactive"?: bool }] }
action 1 — insert: { ..., "action": 1, "companyId": int, "name": str,
  "description"?: str, "durationMinutes"?: int, "capacity"?: int, "machineType"?: str }
action 2 — update (only keys sent): { ..., "action": 2, "companyId": int,
  "reservationServiceId": int, ...fields }
action 3 — deactivate: { ..., "action": 3, "companyId": int, "reservationServiceId": int }
→ { "result": [{ "reservationServices": [...] }] }

durationMinutes / capacity left empty = taken from dbo.machines of machineType
(longest cycle, machines in service); neither = 60 min, 1 booking.
""",
    dependencies=[Depends(require_company_admin_on_write("reservationServices"))],
)
def reservation_services(json: dict):
    return reservation_catalog_sp(json, "sp_reservationServices")


@router.post(
    "/reservationHours",
    summary="Business hours for reservations (per company and weekday)",
    description="""
dayOfWeek: 0 = Monday … 6 = Sunday. No row = closed that day.
action 0 (or omit) — list: { "reservationHours": [{ "companyId": int }] }
action 1 — set a day: { ..., "action": 1, "companyId": int, "dayOfWeek": int,
  "openTime": "HH:MM", "closeTime": "HH:MM" }
action 3 — close a day: { ..., "action": 3, "companyId": int, "dayOfWeek": int }
→ { "result": [{ "reservationHours": [{ "dayOfWeek", "openTime", "closeTime" }] }] }
""",
    dependencies=[Depends(require_company_admin_on_write("reservationHours"))],
)
def reservation_hours(json: dict):
    return reservation_catalog_sp(json, "sp_reservationHours")


@router.post(
    "/reservationHolidays",
    summary="Holidays / special days (per company and date)",
    description="""
A date here replaces that day's weekly hours (/reservationHours).
openTime + closeTime empty = closed all day; both set = that day's hours.
action 0 (or omit) — list: { "reservationHolidays": [{ "companyId": int,
  "fromDate"?: "YYYY-MM-DD" (default today, Hermosillo), "toDate"?: "YYYY-MM-DD" }] }
action 1 — set a date: { ..., "action": 1, "companyId": int,
  "holidayDate": "YYYY-MM-DD", "name"?: str, "openTime"?: "HH:MM", "closeTime"?: "HH:MM" }
action 3 — remove a date: { ..., "action": 3, "companyId": int, "holidayDate": "YYYY-MM-DD" }
→ { "result": [{ "reservationHolidays": [{ "holidayDate", "name", "isOpen",
    "openTime", "closeTime" }] }] }
""",
    dependencies=[Depends(require_company_admin_on_write("reservationHolidays"))],
)
def reservation_holidays(json: dict):
    return reservation_catalog_sp(json, "sp_reservationHolidays")


@router.post(
    "/reservationSchedule",
    summary="The company's schedule day by day (weekly hours + holidays)",
    description="""
Read-only. What the agents and the kiosk ask: is it open on a date, and when.
{ "reservationSchedule": [{ "companyId": int,
  "fromDate"?: "YYYY-MM-DD" (default today, Hermosillo), "days"?: int (default 7, max 62) }] }
→ { "result": [{ "reservationSchedule": [{ "date": "YYYY-MM-DD",
    "dayOfWeek": 0-6 (0 = lunes), "weekday": "lunes", "isOpen": bool,
    "openTime": "HH:MM"|null, "closeTime": "HH:MM"|null,
    "isHoliday": bool, "holidayName": str|null }] }] }
""",
)
def reservation_schedule(json: dict):
    return reservation_catalog_sp(json, "sp_reservationSchedule")


@router.post(
    "/reservations/migrate",
    dependencies=[Depends(require_worker_key)],
    summary="Create reservation tables, catalogs + SPs on the database (idempotent)",
)
def reservations_migrate():
    try:
        result = run_migration()
        return JSONResponse(result, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
