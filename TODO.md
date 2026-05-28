# Ticket Notifications + Receipt HTML Endpoint Plan

## Goal
Maintain ticket notification endpoints and add one new backend endpoint to persist receipt HTML in Azure Blob Storage:
- `POST /api/tickets/{ticketId}/send-sms`
- `POST /api/tickets/{ticketId}/send-whatsapp`
- `POST /api/tickets/receipt-html`

## Steps

### Existing Notifications Work
1. [x] Create `modules/ticket_notifications.py`:
   - E.164 phone validation
   - Twilio client setup via env vars
   - send SMS helper
   - send WhatsApp helper
   - message builder with optional `message` and `receiptUrl`
2. [x] Add doc description files:
   - `docs_description/tickets_send_sms.txt`
   - `docs_description/tickets_send_whatsapp.txt`
3. [x] Update `routes_/tickets.py`:
   - keep `/one_tickets`
   - add `/api/tickets/{ticketId}/send-sms`
   - add `/api/tickets/{ticketId}/send-whatsapp`
   - request body schema with `phone`, optional `message`, optional `receiptUrl`

### New Receipt HTML Persistence Work
4. [x] Add dependency in `requirements.txt`:
   - `azure-storage-blob`
5. [x] Create `modules/ticket_receipts.py`:
   - payload validation for `incomeId` and `html`
   - Azure Blob client setup from env var `AZURE_STORAGE_CONNECTION_STRING`
   - blob path format `receipts/{year}/{month}/receipt_{incomeId}.html`
   - upload with `content_type="text/html"` and `overwrite=True`
   - return `{success, receiptUrl}`
6. [x] Add endpoint docs file:
   - `docs_description/tickets_receipt_html.txt`
7. [x] Update `routes_/tickets.py`:
   - load receipt-html docstring
   - add request model `TicketReceiptHtmlRequest`
   - add route `POST /api/tickets/receipt-html`
   - return 400 for validation errors, 500 for runtime/upload errors

### Remaining Validation / QA
8. [ ] Run API tests with curl:
   - happy path upload
   - validation failures
   - overwrite behavior
   - env/config failure
9. [ ] Regression check existing ticket endpoints:
   - `/one_tickets`
   - `/api/tickets/{ticketId}/send-sms`
   - `/api/tickets/{ticketId}/send-whatsapp`
10. [ ] Mark testing complete and summarize outcomes.
