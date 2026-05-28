
from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel

from modules.tickets import one_tickets_sp
from modules.ticket_notifications import send_ticket_sms, send_ticket_whatsapp
from modules.ticket_receipts import save_receipt_html
from starlette.responses import JSONResponse

router = APIRouter()

# Read one ticket docstring from the file
with open("./docs_description/tickets_one.txt", "r") as file:
    ticket_one_docstring = file.read()

with open("./docs_description/tickets_send_sms.txt", "r") as file:
    ticket_send_sms_docstring = file.read()

with open("./docs_description/tickets_send_whatsapp.txt", "r") as file:
    ticket_send_whatsapp_docstring = file.read()

with open("./docs_description/tickets_receipt_html.txt", "r") as file:
    ticket_receipt_html_docstring = file.read()


class TicketNotificationRequest(BaseModel):
    phone: str
    message: Optional[str] = None
    receiptUrl: Optional[str] = None


class TicketReceiptHtmlRequest(BaseModel):
    incomeId: int
    branchId: int
    html: str
    fileName: Optional[str] = None


@router.post("/one_tickets", summary="one ticket", description=ticket_one_docstring)
def one_tickets(json: dict):
    return one_tickets_sp(json)


@router.post("/api/tickets/{ticketId}/send-sms", summary="Send ticket by SMS", description=ticket_send_sms_docstring)
def send_sms(ticketId: str, payload: TicketNotificationRequest):
    try:
        result = send_ticket_sms(
            ticket_id=ticketId,
            phone=payload.phone,
            message=payload.message,
            receipt_url=payload.receiptUrl
        )
        return JSONResponse(content=result, status_code=200)
    except ValueError as e:
        return JSONResponse(content={"error": str(e)}, status_code=400)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


@router.post("/api/tickets/{ticketId}/send-whatsapp", summary="Send ticket by WhatsApp", description=ticket_send_whatsapp_docstring)
def send_whatsapp(ticketId: str, payload: TicketNotificationRequest):
    try:
        result = send_ticket_whatsapp(
            ticket_id=ticketId,
            phone=payload.phone,
            message=payload.message,
            receipt_url=payload.receiptUrl
        )
        return JSONResponse(content=result, status_code=200)
    except ValueError as e:
        return JSONResponse(content={"error": str(e)}, status_code=400)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


@router.post("/api/tickets/receipt-html", summary="Persist receipt HTML", description=ticket_receipt_html_docstring)
def save_receipt(payload: TicketReceiptHtmlRequest):
    try:
        result = save_receipt_html(
            income_id=payload.incomeId,
            branch_id=payload.branchId,
            html=payload.html,
            file_name=payload.fileName
        )
        return JSONResponse(content=result, status_code=200)
    except ValueError as e:
        return JSONResponse(content={"success": False, "error": str(e)}, status_code=400)
    except RuntimeError as e:
        return JSONResponse(content={"success": False, "error": str(e)}, status_code=500)
    except Exception as e:
        return JSONResponse(content={"success": False, "error": str(e)}, status_code=500)
