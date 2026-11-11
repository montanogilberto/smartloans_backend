from fastapi import APIRouter, Body, Depends

from modules.locationHosts import all_locationHosts_sp, status_locationHosts_sp
from security.rate_limit import rate_limit, row_field
from security.session_tokens import require_company_staff_session

router = APIRouter()

# Red GMO host candidates. No create/delete route: rows are written in-process by
# the WhatsApp agent path (modules/whatsappReservations). Reads return the
# business contact's phone, so both routes need the worker key or a session of
# an admin/manager of that company (body {"locationHosts": [{companyId, userId, ...}]}).
_ADMIN_ROLES = {"admin", "manager"}
_guard = Depends(require_company_staff_session("locationHosts", roles=_ADMIN_ROLES))

with open("./docs_description/locationHosts_all.txt", "r", encoding="utf-8") as file:
    locationHosts_all_docstring = file.read()
with open("./docs_description/locationHosts_status.txt", "r", encoding="utf-8") as file:
    locationHosts_status_docstring = file.read()


@router.post("/all_locationHosts", summary="all Location Hosts (Red GMO)",
             description=locationHosts_all_docstring, dependencies=[_guard])
def all_locationHosts(json_file: dict = Body(...)):
    return all_locationHosts_sp(json_file)


@router.post("/locationHosts/status", summary="Move a host candidate through the pipeline",
             description=locationHosts_status_docstring,
             dependencies=[_guard, Depends(rate_limit("location_host_status", per_ip=300, per_target=30,
                                                      window=3600,
                                                      target=row_field("locationHosts", "locationHostId")))])
def status_locationHosts(json_file: dict = Body(...)):
    return status_locationHosts_sp(json_file)
