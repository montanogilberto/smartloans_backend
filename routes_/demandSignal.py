from fastapi import APIRouter, Body, Depends

from modules.demandSignals import all_demandSignals_sp, one_demandSignals_sp, zone_summary_demandSignals_sp
from security.session_tokens import require_company_staff_session

router = APIRouter()

# Read-only. No create/delete route: rows are written in-process by the WhatsApp
# agent path (modules/whatsappReservations → modules/demandSignals.record_demand_signal).
# Reads need the worker key, or a session of an admin/manager of that company
# (body {"demandSignals": [{companyId, userId, ...}]}).
_ADMIN_ROLES = {"admin", "manager"}
_guard = Depends(require_company_staff_session("demandSignals", roles=_ADMIN_ROLES))

with open("./docs_description/demandSignals_all.txt", "r", encoding="utf-8") as file:
    demandSignals_all_docstring = file.read()
with open("./docs_description/demandSignals_one.txt", "r", encoding="utf-8") as file:
    demandSignals_one_docstring = file.read()
with open("./docs_description/demandSignals_zoneSummary.txt", "r", encoding="utf-8") as file:
    demandSignals_zoneSummary_docstring = file.read()


@router.post("/all_demandSignals", summary="all DemandSignals", description=demandSignals_all_docstring,
             dependencies=[_guard])
def all_demandSignals(json_file: dict = Body(...)):
    return all_demandSignals_sp(json_file)


@router.post("/one_demandSignals", summary="one DemandSignal", description=demandSignals_one_docstring,
             dependencies=[_guard])
def one_demandSignals(json_file: dict = Body(...)):
    return one_demandSignals_sp(json_file)


@router.post("/demandSignals/zoneSummary", summary="DemandSignals by zone (demand map)",
             description=demandSignals_zoneSummary_docstring, dependencies=[_guard])
def zone_summary_demandSignals(json_file: dict = Body(...)):
    return zone_summary_demandSignals_sp(json_file)
