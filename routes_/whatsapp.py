

from fastapi import APIRouter, Request
from starlette.responses import PlainTextResponse, JSONResponse
from modules.whatsapp import log_message_to_database

router = APIRouter()


@router.post("/whatsapp", summary="WhatsApp Webhook", description="Endpoint to handle incoming WhatsApp messages")
async def whatsapp_webhook(request: Request):
    """
    Webhook to receive WhatsApp messages and respond via Twilio API.
    """
    try:
        # Parse incoming JSON data from the request
        data = await request.json()

        # Extract messages from the JSON payload
        messages = data.get("messages", [])

        if not messages:
            # If no messages are found in the request body, return an error response
            return PlainTextResponse("No messages found in the request", status_code=400)

        # Loop through all messages and log them to the database
        responses = []
        for message in messages:
            phone_number = message.get("phoneNumber", "")
            message_body = message.get("messageBody", "")
            response_body = message.get("responseBody", "")
            direction = message.get("direction", "")
            status = message.get("status", "")

            # Get the action parameter; raise an error if it's missing
            if "action" not in message:
                return JSONResponse(content={"error": "Action parameter is required in the message."}, status_code=400)
            action = message["action"]

            # Log the message to the database
            db_response = log_message_to_database(
                phone_number, message_body, response_body, direction, status, action
            )

            # Append the database response to the list of responses
            responses.append(db_response)

        # Generate a response message
        if len(responses) == 1:
            # For a single message, return just the Twilio response
            return PlainTextResponse(responses[0])
        else:
            # For multiple messages, return a JSON response
            return JSONResponse(content={"responses": responses})

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)