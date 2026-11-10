from fastapi import APIRouter, Body, Depends

from modules.voiceCalls import place_call
from security.rate_limit import rate_limit, row_field
from security.session_tokens import require_company_staff_session

router = APIRouter()

with open("docs_description/voiceCalls.txt", "r", encoding="utf-8") as f:
    voiceCalls_docstring = f.read()


@router.post(
    "/voiceCalls/place",
    summary="The virtual Secretary phones a client",
    description=voiceCalls_docstring,
    dependencies=[
        Depends(require_company_staff_session("voiceCall")),
        # A real phone rings: a client can't be called over and over.
        Depends(rate_limit("voice_call", per_ip=60, per_target=3, window=3600,
                           target=row_field("voiceCall", "clientId"))),
    ],
)
def voice_call_place(json_file: dict = Body(...)):
    return place_call(json_file)
