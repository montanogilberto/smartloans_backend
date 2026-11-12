# modules/whatsapp.py

from fastapi.responses import JSONResponse
from twilio.twiml.messaging_response import MessagingResponse
from databases import connection
import json
import logging

logger = logging.getLogger(__name__)

def log_outbound_message(json_file: dict) -> int | None:
    """Logs ONE WhatsApp message to dbo.whatsappMessages (sp_whatsapp_messages action 1)
    and returns its messageId, so the caller can link the Meta wamid to it
    (whatsappMessageDeliveries). Same row as log_message_to_database writes;
    that function keeps its TwiML return for the legacy Twilio callers.

    json_file: { "phoneNumber", "messageBody", "responseBody"?, "direction", "status" }
    Returns None on any error (never raises: a log hiccup must not stop a send).
    Logs only the phone's last 4 digits, never the text."""
    payload = json.dumps({"messages": [{
        "phoneNumber": json_file.get("phoneNumber"),
        "messageBody": json_file.get("messageBody"),
        "responseBody": json_file.get("responseBody") or "",
        "direction": json_file.get("direction"),
        "status": json_file.get("status"),
        "action": 1,
    }]})
    tail = str(json_file.get("phoneNumber") or "")[-4:]
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_whatsapp_messages @pjsonfile = %s", (payload,))
        row = cursor.fetchone()
        conn.commit()
        # Result columns: value (new messageId since 2026-11-12), msg, error.
        if not row or (len(row) > 2 and row[2] == "1"):
            logger.warning("[log_outbound_message] not logged | phone=…%s msg=%s",
                           tail, row[1] if row and len(row) > 1 else None)
            return None
        try:
            return int(row[0]) if row[0] not in (None, "") else None
        except (TypeError, ValueError):
            return None  # SP not yet redeployed with the id return: the row is still logged
    except Exception:
        logger.exception("[log_outbound_message] error | phone=…%s", tail)
        return None
    finally:
        if conn:
            conn.close()


def log_message_to_database(phone_number, message_body, response_body, direction, status, action):
    """
    Log incoming or outgoing WhatsApp messages to the database using a stored procedure.
    """
    logger.info(
        "[log_message_to_database] start | phone=%s direction=%s status=%s action=%s",
        phone_number,
        direction,
        status,
        action
    )
    # Prepare the JSON payload for the stored procedure
    request_data = {
        "messages": [
            {
                "phoneNumber": phone_number,
                "messageBody": message_body,
                "responseBody": response_body,
                "direction": direction,
                "status": status,
                "action": action
            }
        ]
    }

    # Convert request data to JSON string
    json_request = json.dumps(request_data)

    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        logger.info("[log_message_to_database] executing stored procedure sp_whatsapp_messages")
        cursor.execute("EXEC sp_whatsapp_messages @pjsonfile = %s", (json_request,))
        conn.commit()
        logger.info("[log_message_to_database] stored procedure committed")

        # Fetch the result from the stored procedure
        result_row = cursor.fetchone()

        if not result_row or not result_row[0]:
            # If the result is empty or None, return a custom error message
            logger.warning("[log_message_to_database] no data returned from stored procedure")
            return "Error: No data returned from stored procedure."

        # Ensure the result is valid JSON before parsing
        try:
            json_result = json.loads(result_row[0])
        except json.JSONDecodeError as e:
            logger.exception("[log_message_to_database] JSON decode error: %s", str(e))
            return f"Error decoding JSON from SQL Server response: {str(e)}"

        # Generate Twilio response
        response = MessagingResponse()
        reply = response.message()
        reply.body(response_body if response_body else "Thank you for your message!")
        logger.info("[log_message_to_database] success | twiml_response_generated=true")
        return str(response)

    except Exception as e:
        logger.exception("[log_message_to_database] error: %s", str(e))
        # Return the error message
        return f"Error logging message to database: {str(e)}"
    finally:
        if conn:
            conn.close()
