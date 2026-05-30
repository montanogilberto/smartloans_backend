
import json
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from modules.tickets import one_tickets_sp, one_ticket_tracking_sp, ticket_redirect_sp
from modules.ticket_notifications import send_ticket_sms, send_ticket_whatsapp
from modules.ticket_receipts import save_receipt_html
from starlette.responses import JSONResponse, RedirectResponse

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

with open("./docs_description/ticket_tracking_one.txt", "r") as file:
    ticket_tracking_one_docstring = file.read()

with open("./docs_description/tickets_redirect.txt", "r") as file:
    ticket_redirect_docstring = file.read()


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


@router.post("/one_ticket_tracking", summary="one ticket tracking", description=ticket_tracking_one_docstring)
def one_ticket_tracking(json: dict):
    return one_ticket_tracking_sp(json)


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


@router.get("/r/{short_code}", summary="Redirect ticket receipt", description=ticket_redirect_docstring)
async def redirect_ticket(short_code: str):
    payload = {
        "ticket": [
            {
                "action": "redirect",
                "shortCode": short_code
            }
        ]
    }

    response = ticket_redirect_sp(payload)

    if response.status_code != 200:
        raise HTTPException(status_code=500, detail="Failed to fetch ticket redirect data")

    result = response.body.decode("utf-8")
    result_json = json.loads(result)

    tickets = result_json.get("tickets", [])
    if not tickets:
        raise HTTPException(status_code=404, detail="Ticket not found")

    receipt_url = tickets[0].get("receiptUrl")
    if not receipt_url:
        raise HTTPException(status_code=404, detail="Ticket not found")

    return RedirectResponse(url=receipt_url, status_code=302)
