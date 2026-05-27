# Ticket Notifications Endpoints Plan

## Goal
Add two backend endpoints to send ticket notifications via provider APIs (no DB changes):
- `POST /api/tickets/{ticketId}/send-sms`
- `POST /api/tickets/{ticketId}/send-whatsapp`

## Steps
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
4. [x] Validate Python syntax for changed files.
5. [x] Mark all tasks completed and summarize.
