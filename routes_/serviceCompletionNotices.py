from fastapi import APIRouter, Body, Depends

from modules.serviceCompletionNotices import send, status
from security.rate_limit import rate_limit, row_field
from security.session_tokens import require_company_staff_session

router = APIRouter()

with open("docs_description/serviceCompletionNotices.txt", "r", encoding="utf-8") as f:
    serviceCompletionNotices_docstring = f.read()


@router.post(
    "/serviceCompletionNotices/status",
    summary="Which recent sales can be told 'tu servicio está listo'",
    description=serviceCompletionNotices_docstring,
    dependencies=[Depends(require_company_staff_session("serviceCompletionNotices"))],
)
def service_completion_status(json_file: dict = Body(...)):
    return status(json_file)


@router.post(
    "/serviceCompletionNotices/send",
    summary="Tell the customer their service is ready (push → WhatsApp → SMS)",
    description=serviceCompletionNotices_docstring,
    dependencies=[
        Depends(require_company_staff_session("serviceCompletionNotice")),
        Depends(rate_limit("service_completion", per_ip=300, per_target=5, window=3600,
                           target=row_field("serviceCompletionNotice", "incomeId"))),
    ],
)
async def service_completion_send(json_file: dict = Body(...)):
    return await send(json_file)
