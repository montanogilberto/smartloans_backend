from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse

from modules import loanTickets

router = APIRouter()


@router.get(
    "/comprobante/{token}",
    summary="Open a loan transaction ticket",
    description="Signed loan ticket link (modules/loanTickets.py, RFC-014). Renders the "
                "comprobante of a funding for one party (borrower or lender) from the current "
                "rows: amount, dates, status history and transfer evidence. 404 for an "
                "invalid/unsigned token or when LOAN_TICKET_LINK_SECRET is not set.",
)
def open_loan_ticket(token: str):
    verified = loanTickets.verify_token(token)
    if not verified:
        raise HTTPException(status_code=404, detail="Comprobante no encontrado")
    company_id, kind, source_id, recipient = verified
    page = loanTickets.render_funding_ticket(company_id, source_id, recipient) if kind == "funding" else None
    if not page:
        raise HTTPException(status_code=404, detail="Comprobante no encontrado")
    return HTMLResponse(page, headers={"Cache-Control": "no-store"})
