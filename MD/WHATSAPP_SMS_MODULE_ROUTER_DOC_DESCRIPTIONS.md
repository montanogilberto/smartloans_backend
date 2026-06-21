# WhatsApp and SMS - Module, Router, and Doc Descriptions

## Overview

This document summarizes how WhatsApp and SMS notifications are implemented in the backend, including:

- **Module logic** (message validation, composition, and provider calls)
- **Router endpoints** (API paths and request/response behavior)
- **Doc description sources** used by route metadata

Primary implementation files:

- `modules/ticket_notifications.py`
- `routes_/tickets.py`
- `routes_/whatsapp.py`
- `docs_description/tickets_send_sms.txt`
- `docs_description/tickets_send_whatsapp.txt`
- `main.py` (router registration)

---

## 1) Module

### File
`modules/ticket_notifications.py`

### Purpose
Provides outbound notification helpers for:

- **SMS** via Twilio
- **WhatsApp** via Twilio WhatsApp API

### Main functions

- `_validate_phone_e164(phone: str) -> None`  
  Validates destination phone numbers with E.164 format:
  - Example valid format: `+521234567890`
  - Raises `ValueError` on invalid input

- `_build_message(ticket_id: str, message: Optional[str], receipt_url: Optional[str]) -> str`  
  Builds message body:
  - Uses custom `message` when provided
  - Fallback message: `Ticket #{ticket_id} update.`
  - Appends `Receipt: {receipt_url}` when `receipt_url` is present

- `_twilio_client() -> Client`  
  Creates Twilio client using environment variables:
  - `TWILIO_ACCOUNT_SID`
  - `TWILIO_AUTH_TOKEN`
  - Raises `ValueError` if credentials are missing

- `send_ticket_sms(ticket_id: str, phone: str, message: Optional[str] = None, receipt_url: Optional[str] = None) -> Dict[str, Any]`  
  Sends SMS and returns structured result:
  - Validates phone
  - Requires `TWILIO_SMS_FROM`
  - Calls `client.messages.create(...)`
  - Returns fields such as:
    - `channel` (`sms`)
    - `ticketId`
    - `to`
    - `provider` (`twilio`)
    - `messageSid`
    - `status`

- `send_ticket_whatsapp(ticket_id: str, phone: str, message: Optional[str] = None, receipt_url: Optional[str] = None) -> Dict[str, Any]`  
  Sends WhatsApp message and returns structured result:
  - Validates phone
  - Requires `TWILIO_WHATSAPP_FROM`
  - Normalizes `from` value to `whatsapp:...` format
  - Sends to `whatsapp:{phone}`
  - Returns fields such as:
    - `channel` (`whatsapp`)
    - `ticketId`
    - `to`
    - `provider` (`twilio`)
    - `messageSid`
    - `status`

---

## 2) Router

## File
`routes_/tickets.py`

### Related request models

- `TicketNotificationRequest`
  - `phone: str` (required)
  - `message: Optional[str] = None`
  - `receiptUrl: Optional[str] = None`

### Endpoints

- `POST /api/tickets/{ticketId}/send-sms`  
  Summary: **Send ticket by SMS**  
  Description loaded from: `docs_description/tickets_send_sms.txt`

  Flow:
  1. Receives `ticketId` path param and notification payload
  2. Calls `send_ticket_sms(...)`
  3. Returns:
     - `200` with Twilio send result on success
     - `400` for validation/config issues (`ValueError`)
     - `500` for unexpected errors

- `POST /api/tickets/{ticketId}/send-whatsapp`  
  Summary: **Send ticket by WhatsApp**  
  Description loaded from: `docs_description/tickets_send_whatsapp.txt`

  Flow:
  1. Receives `ticketId` path param and notification payload
  2. Calls `send_ticket_whatsapp(...)`
  3. Returns:
     - `200` with Twilio send result on success
     - `400` for validation/config issues (`ValueError`)
     - `500` for unexpected errors

---

### File
`routes_/whatsapp.py`

### Endpoint

- `POST /whatsapp`  
  Summary: **WhatsApp Webhook**  
  Description: Endpoint to handle incoming WhatsApp messages

  Behavior:
  - Expects JSON with `messages` array
  - For each message, extracts:
    - `phoneNumber`
    - `messageBody`
    - `responseBody`
    - `direction`
    - `status`
    - `action` (required)
  - Logs messages through `modules.whatsapp.log_message_to_database(...)`
  - Returns:
    - `400` when `messages` is missing/empty or required action missing
    - `PlainTextResponse` for single processed message
    - `JSONResponse` for multiple processed messages
    - `500` on unhandled exceptions

---

## 3) Doc Descriptions

### File
`docs_description/tickets_send_sms.txt`

Defines API docs text for SMS endpoint:

- Explains request body fields:
  - `phone` (required, E.164)
  - `message` (optional)
  - `receiptUrl` (optional)
- States Twilio outbound SMS usage
- Lists required env vars:
  - `TWILIO_ACCOUNT_SID`
  - `TWILIO_AUTH_TOKEN`
  - `TWILIO_SMS_FROM`

### File
`docs_description/tickets_send_whatsapp.txt`

Defines API docs text for WhatsApp endpoint:

- Explains request body fields:
  - `phone` (required, E.164)
  - `message` (optional)
  - `receiptUrl` (optional)
- States Twilio WhatsApp API usage
- Lists required env vars:
  - `TWILIO_ACCOUNT_SID`
  - `TWILIO_AUTH_TOKEN`
  - `TWILIO_WHATSAPP_FROM` (example: `whatsapp:+14155238886`)

---

## 4) Router Registration

### File
`main.py`

Routers are enabled in the FastAPI app with:

- `app.include_router(whatsapp.router)`
- `app.include_router(tickets.router)`

This makes both WhatsApp webhook and ticket notification endpoints active in the API.

---

## 5) Environment Variables Summary

For outbound SMS/WhatsApp notifications to work, configure:

- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_SMS_FROM` (for SMS sender)
- `TWILIO_WHATSAPP_FROM` (for WhatsApp sender, usually `whatsapp:+...`)

---

## 6) End-to-End Flow (Ticket Notifications)

1. Client calls one of:
   - `POST /api/tickets/{ticketId}/send-sms`
   - `POST /api/tickets/{ticketId}/send-whatsapp`
2. Router validates/parses payload and delegates to module
3. Module validates phone number and builds message
4. Module sends message through Twilio client
5. Router returns normalized JSON response with provider metadata
