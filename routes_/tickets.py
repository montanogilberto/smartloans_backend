
import json
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from modules.tickets import one_tickets_sp, one_ticket_tracking_sp, ticket_redirect_sp
from modules.ticket_notifications import send_ticket_sms, send_ticket_whatsapp
from modules.ticket_receipts import save_receipt_html
from starlette.responses import HTMLResponse, JSONResponse, RedirectResponse

from databases import connection
from modules import receiptLinks
from modules.income import _get_final_total_and_discount

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
        # payload.fileName is ignored: the POS sends receipt_{incomeId}.html,
        # a guessable name. The blob gets a random one (ticket_receipts).
        result = save_receipt_html(
            income_id=payload.incomeId,
            branch_id=payload.branchId,
            html=payload.html,
        )
        return JSONResponse(content=result, status_code=200)
    except ValueError as e:
        return JSONResponse(content={"success": False, "error": str(e)}, status_code=400)
    except RuntimeError as e:
        return JSONResponse(content={"success": False, "error": str(e)}, status_code=500)
    except Exception as e:
        return JSONResponse(content={"success": False, "error": str(e)}, status_code=500)


@router.get("/r/{short_code}", summary="Retired receipt short link", description=ticket_redirect_docstring)
async def redirect_ticket(short_code: str):
    # Retired: short codes are T{incomeId}, so counting up through them handed
    # out every customer's receipt. Customer links are /recibo/{token} now.
    return JSONResponse(content={"error": "This receipt link is no longer valid."}, status_code=410)


@router.get("/recibo/f/{token}", summary="Open a signed receipt file",
            description="Signed link to one stored receipt file (arcade chip tickets). "
                        "Redirects to a short-lived read-only URL.")
def open_receipt_file(token: str):
    path = receiptLinks.verify_file_token(token)
    if not path:
        raise HTTPException(status_code=404, detail="Recibo no encontrado")
    return RedirectResponse(url=receiptLinks.sas_url_for_path(path), status_code=302,
                            headers={"Cache-Control": "no-store"})


@router.get("/recibo/{token}", summary="Open a customer receipt",
            description="Signed customer receipt link (modules/receiptLinks.py). Redirects to a "
                        "short-lived read-only URL of the receipt, or shows a purchase summary "
                        "while the ticket has not been printed yet.")
def open_receipt(token: str):
    verified = receiptLinks.verify_token(token)
    if not verified:
        raise HTTPException(status_code=404, detail="Recibo no encontrado")
    company_id, income_id = verified
    no_store = {"Cache-Control": "no-store"}

    response = ticket_redirect_sp({"ticket": [{"action": "redirect", "shortCode": f"T{income_id}"}]})
    # A sale that was never printed has no ticket row: the SP's FOR JSON
    # returns NULL and ticket_redirect_sp answers 500 — same as "no receipt".
    tickets = (json.loads(response.body).get("tickets") or []) if response.status_code == 200 else []
    stored_url = tickets[0].get("receiptUrl") if tickets else None
    if stored_url:
        try:
            return RedirectResponse(url=receiptLinks.sas_url(stored_url), status_code=302, headers=no_store)
        except Exception as e:
            print(f"[tickets] receipt SAS failed for income {income_id}: {e}")

    conn = None
    try:
        conn = connection()
        total, discount, _promo = _get_final_total_and_discount(conn, income_id, company_id)
    finally:
        if conn:
            conn.close()
    if total is None:
        raise HTTPException(status_code=404, detail="Recibo no encontrado")
    return HTMLResponse(receiptLinks.summary_page(income_id, total, discount), headers=no_store)
