# modules/whatsapp.py

from fastapi.responses import JSONResponse
from twilio.twiml.messaging_response import MessagingResponse
from databases import connection
import json
import logging

logger = logging.getLogger(__name__)

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
