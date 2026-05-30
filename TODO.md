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

### DB Connectivity + Error Visibility Plan
11. [x] Update `databases.py`:
   - prioritize environment variables for DB connection
   - remove hardcoded credential usage path
   - keep connection wrapper behavior unchanged
12. [x] Improve DB connection error diagnostics:
   - wrap `pymssql.connect` with explicit exception handling
   - raise actionable RuntimeError message for API layer visibility
13. [ ] Re-test endpoints:
   - `GET /all_companies`
   - `POST /api/tickets/receipt-html`
14. [ ] Summarize root cause and final config requirements.

### New Ticket Tracking Endpoint Plan
15. [x] Analyze current ticket structure (`routes_/tickets.py`, `modules/tickets.py`, `main.py`).
16. [x] Create docs file:
   - `docs_description/ticket_tracking_one.txt`
17. [x] Update module:
   - add `one_ticket_tracking_sp` in `modules/tickets.py`
   - execute `EXEC sp_ticket_tracking @pjsonfile = %s`
   - parse JSON response and return `JSONResponse`
18. [x] Update route:
   - import `one_ticket_tracking_sp` in `routes_/tickets.py`
   - load docstring from `docs_description/ticket_tracking_one.txt`
   - add `POST /one_ticket_tracking`
19. [x] Run syntax sanity check on updated files.
20. [x] Summarize implementation.

### New Ticket Redirect Endpoint Plan
21. [x] Add reusable SQL JSON helper and redirect service function:
   - update `modules/tickets.py`
   - add `execute_sp_json(...)`
   - add `ticket_redirect_sp(short_code)` calling `EXEC dbo.sp_ticket_redirect @pjsonfile = %s`
22. [x] Add redirect route:
   - update `routes_/tickets.py`
   - add `GET /r/{short_code}`
   - return `404` when not found
   - return `RedirectResponse(..., status_code=302)` to `receiptUrl`
23. [ ] Run syntax sanity check for updated files.
24. [ ] Summarize implementation.
