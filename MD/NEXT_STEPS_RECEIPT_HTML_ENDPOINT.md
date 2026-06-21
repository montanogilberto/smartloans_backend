# Next Steps for Developer: `POST /api/tickets/receipt-html`

## Current Status
The backend endpoint for receipt HTML persistence has **not been implemented yet** in this repository session.  
No tests were executed for this new endpoint.

---

## Objective
Create a FastAPI endpoint to persist generated receipt HTML to Azure Blob Storage and return a public URL.

### Endpoint
`POST /api/tickets/receipt-html`

### Request Body
```json
{
  "incomeId": 12345,
  "branchId": 1,
  "html": "<html>...</html>",
  "fileName": "receipt_12345.html"
}
```

### Expected Response
```json
{
  "success": true,
  "receiptUrl": "https://imageprofile.blob.core.windows.net/ticketspos/receipts/2026/05/receipt_12345.html"
}
```

---

## Implementation Plan

### 1) Add Azure Blob dependency
Update `requirements.txt`:
- Add `azure-storage-blob` (latest compatible stable version).

---

### 2) Create module for receipt HTML upload
Create new file: `modules/ticket_receipts.py`

Implement:
- Pydantic model (or route-level model) validation support for:
  - `incomeId` required
  - `html` required and non-empty
  - `branchId` optional/required per business rules (requested body includes it)
  - `fileName` optional
- Upload function to Azure Blob:
  - Read connection string from env: `AZURE_STORAGE_CONNECTION_STRING`
  - Container: `ticketspos`
  - Blob path format: `receipts/{year}/{month}/receipt_{incomeId}.html`
  - Content-Type: `text/html`
  - `overwrite=True`
- Return dict with:
  - `success: True`
  - `receiptUrl: <public blob url>`

Suggested function signatures:
```python
def build_receipt_blob_path(income_id: int, now: datetime | None = None) -> str: ...
def save_receipt_html(income_id: int, branch_id: int, html: str, file_name: str | None = None) -> dict: ...
```

Error handling:
- Missing/invalid payload -> 400
- Missing env config -> 500 with clear message
- Azure upload failure -> 500 with clear message

---

### 3) Add route in tickets router
Edit file: `routes_/tickets.py`

Add:
- Request model for receipt upload payload
- New endpoint:
  - `@router.post("/api/tickets/receipt-html", ...)`
- Route behavior:
  - Validate payload
  - Call module upload function
  - Return JSON response with `{success, receiptUrl}`
  - Consistent error responses (400/500)

---

### 4) Add API documentation description file
Create:
- `docs_description/tickets_receipt_html.txt`

Include:
- Purpose of endpoint
- Request contract
- Response contract
- Notes about public URL and overwrite behavior

Then wire it in `routes_/tickets.py` similar to existing `tickets_send_sms` / `tickets_send_whatsapp` doc loading pattern.

---

### 5) Verify app routing
`main.py` already includes `tickets.router`, so no additional include is likely needed.  
Only verify route availability once implemented.

---

### 6) Update project TODO tracking
Edit `TODO.md`:
- Add checklist section for receipt HTML endpoint implementation and testing.
- Mark items progressively as completed.

---

## Testing Plan (Curl)

Run API locally and test with curl.

### A. Happy Path
```bash
curl -X POST http://localhost:8000/api/tickets/receipt-html \
  -H "Content-Type: application/json" \
  -d '{
    "incomeId": 12345,
    "branchId": 1,
    "html": "<html><body><h1>Receipt 12345</h1></body></html>",
    "fileName": "receipt_12345.html"
  }'
```
Expected: `200` + `{ "success": true, "receiptUrl": "https://..." }`

---

### B. Missing HTML
```bash
curl -X POST http://localhost:8000/api/tickets/receipt-html \
  -H "Content-Type: application/json" \
  -d '{
    "incomeId": 12345,
    "branchId": 1,
    "html": ""
  }'
```
Expected: `400`

---

### C. Missing incomeId
```bash
curl -X POST http://localhost:8000/api/tickets/receipt-html \
  -H "Content-Type: application/json" \
  -d '{
    "branchId": 1,
    "html": "<html></html>"
  }'
```
Expected: validation error (`400` or `422` depending on model handling)

---

### D. Overwrite Check
Repeat happy-path request with same `incomeId`.
Expected:
- Success response
- Same path URL
- No failure on overwrite

---

### E. Config Failure Scenario
Temporarily run without valid `AZURE_STORAGE_CONNECTION_STRING`.
Expected: `500` with clear server-side error message.

---

## Suggested Acceptance Criteria
- Endpoint exists and is reachable at `/api/tickets/receipt-html`
- Uploads HTML to `ticketspos` container under `receipts/{year}/{month}/receipt_{incomeId}.html`
- Returns public URL in response payload
- Proper content type (`text/html`)
- Validation and error handling implemented
- Curl tests pass for happy path + key failures
- Existing ticket notification endpoints remain unaffected

---

## Frontend Integration Note
Frontend can call this endpoint once after generating HTML via:
`ReceiptService.generatePrintHTML(...)`
and persist `receiptUrl` for:
- SMS
- WhatsApp
- Email
- QR
- Reprint flows
