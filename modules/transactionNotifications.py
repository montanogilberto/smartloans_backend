from fastapi.responses import JSONResponse
from databases import connection
import json
import httpx
import os
from datetime import datetime

# Observability imports
from observability import timed_integration, log_audit, log_workflow_step, workflow_step


def transactionNotifications_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_transactionNotifications] @pjsonfile = %s", (json.dumps(json_file),))
        # Upsert SP returns ONE row, ONE column -- use fetchone()[0]
        row = cursor.fetchone()
        json_result = row[0] if row else '{"message": "ok"}'

        # Optional: Audit logging for mutations (if the SP doesn't handle it internally)
        # action = json_file.get("action")
        # if action in [2, 3]: # UPDATE or DELETE
        #     entity_id = json_file.get("transactionNotificationId")
        #     log_audit("transactionNotification", entity_id, "status", "old_value", "new_value", action=action)

        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            if cursor: cursor.close()
        except Exception: pass
        try:
            if conn: conn.close()
        except Exception: pass


def all_transactionNotifications_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_transactionNotifications_all] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        # SQL Server may split large FOR JSON output across multiple rows -- always join.
        # Guard against None cells and empty tables (empty table is NOT an error).
        json_result = "".join(row[0] for row in rows if row and row[0])
        if not json_result:
            return JSONResponse(content={"transactionNotifications": []}, status_code=200)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            if cursor: cursor.close()
        except Exception: pass
        try:
            if conn: conn.close()
        except Exception: pass


def one_transactionNotifications_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_transactionNotifications_one] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows if row and row[0])
        if not json_result:
            return JSONResponse(content={"transactionNotifications": []}, status_code=200)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            if cursor: cursor.close()
        except Exception: pass
        try:
            if conn: conn.close()
        except Exception: pass


# --- Connector Endpoints ---

_NOTIF_HUB_ENDPOINT = os.getenv("AZURE_NOTIFICATION_HUB_ENDPOINT")
_NOTIF_HUB_KEY_NAME = os.getenv("AZURE_NOTIFICATION_HUB_KEY_NAME")
_NOTIF_HUB_KEY      = os.getenv("AZURE_NOTIFICATION_HUB_KEY")
_CONTACT_EMAIL_API  = os.getenv("CONTACT_EMAIL_API_ENDPOINT") # Assuming a separate email service


async def dispatch_transactionNotification_connector(payload: dict) -> JSONResponse:
    """
    Create + send the notifications for one transaction. Orchestrates inserts/updates
    via sp_transactionNotifications and dispatches external notifications.
    """
    with workflow_step("Dispatch Transaction Notifications", workflow_name="transaction_notification_dispatch"):
        try:
            company_id  = payload.get("companyId")
            client_id   = payload.get("clientId")
            transaction_id = payload.get("transactionId")
            movement_type = payload.get("movementType")

            if not all([company_id, client_id, transaction_id, movement_type]):
                return JSONResponse({"error": "companyId, clientId, transactionId, and movementType are required"}, status_code=400)

            # Step 1: Insert initial pending notifications for various channels (email, push, in-app)
            # This call to sp_transactionNotifications would typically create one row per channel
            # with status 'pending' based on the movementType and client preferences.
            # For simplicity, let's assume one call can set up all initial channels, or we call it multiple times.
            initial_notification_json = {
                "transactionNotifications": [{
                    "action": 1, # INSERT
                    "companyId": company_id,
                    "clientId": client_id,
                    "transactionId": transaction_id,
                    "movementType": movement_type,
                    "channel": "email", # Example channel
                    "status": "pending",
                    "recipientEmail": payload.get("recipientEmail"),
                    "subject": payload.get("subject"),
                    "messageBody": payload.get("messageBody"),
                    "amount": payload.get("amount"),
                    "currency": payload.get("currency"),
                    "stripeReference": payload.get("stripeReference"),
                    "bankName": payload.get("bankName"),
                    "bankLast4": payload.get("bankLast4")
                }]
            }
            # Assuming the SP can handle multiple inserts or dynamically generates them.
            # If it needs separate calls per channel, this logic would expand.
            insert_result = transactionNotifications_sp(initial_notification_json)
            if insert_result.status_code != 200:
                return insert_result # Propagate error
            
            # The response from transactionNotifications_sp for action 1 should contain the newly created IDs
            # For simplicity, we'll assume the SP returns a list of created notifications or that we'd query for them.
            # For now, let's just make a follow-up query to get the pending notifications for this transaction.
            all_pending_notifications_json = {"transactionNotifications": [{
                "companyId": company_id, "transactionId": transaction_id, "status": "pending"
            }]}
            pending_notifications_res = all_transactionNotifications_sp(all_pending_notifications_json)
            if pending_notifications_res.status_code != 200:
                return pending_notifications_res
            
            pending_notifications = json.loads(pending_notifications_res.body).get("transactionNotifications", [])
            if not pending_notifications:
                # This means the initial insert failed to create any, or was idempotent and already processed.
                return JSONResponse(content={
                    "message": "No new notifications to dispatch or already dispatched.",
                    "transactionNotificationId": None,
                    "status": "no_change",
                    "transactionId": transaction_id
                }, status_code=200)

            results = []
            async with httpx.AsyncClient(timeout=10.0) as client:
                for notification in pending_notifications:
                    channel = notification.get("channel")
                    notif_id = notification.get("transactionNotificationId")
                    update_status = "sent"
                    failure_reason = None

                    if channel == "email":
                        with timed_integration("Gmail_Sender", "send_email") as span:
                            try:
                                # This is a placeholder for actual email sending logic.
                                # In a real scenario, this would call modules.contact_email.send_email
                                email_res = await client.post(
                                    _CONTACT_EMAIL_API + "/send", # Assuming an internal endpoint for email sending
                                    json={
                                        "to": notification.get("recipientEmail"),
                                        "subject": notification.get("subject"),
                                        "body": notification.get("messageBody"),
                                        "companyId": company_id
                                    }
                                )
                                email_res.raise_for_status()
                                span.http_status = email_res.status_code
                            except httpx.HTTPStatusError as e:
                                update_status = "failed"
                                failure_reason = f"Email service error: {e.response.text}"
                                span.http_status = e.response.status_code
                            except Exception as e:
                                update_status = "failed"
                                failure_reason = f"Email dispatch error: {str(e)}"
                                span.http_status = 500

                    elif channel == "push":
                        with timed_integration("Azure_Notification_Hub", "send_push") as span:
                            try:
                                # Placeholder for Azure Notification Hub push
                                # In a real scenario, this would call modules.azure_notifications.send_azure_push
                                # For example, using a simple direct HTTP call to the hub REST API
                                push_headers = {
                                    "Authorization": f"SharedAccessSignature sr={_NOTIF_HUB_ENDPOINT};skn={_NOTIF_HUB_KEY_NAME};sig={_NOTIF_HUB_KEY}",
                                    "Content-Type": "application/json",
                                    "ServiceBusNotification-Format": "gcm", # For Android
                                    "X-WNS-Type": "wns/raw", # For Windows
                                    "X-APNS-Topic": "com.smartloans.app", # For iOS
                                    "Tag": f"user_{client_id}" # Target by user tag
                                }
                                push_body = {
                                    "data": {"message": notification.get("messageBody"), "title": notification.get("subject")}
                                }
                                push_res = await client.post(
                                    _NOTIF_HUB_ENDPOINT + "/messages/?api-version=2015-01", # Simplified path
                                    headers=push_headers, json=push_body
                                )
                                push_res.raise_for_status()
                                span.http_status = push_res.status_code
                            except httpx.HTTPStatusError as e:
                                update_status = "failed"
                                failure_reason = f"Push service error: {e.response.text}"
                                span.http_status = e.response.status_code
                            except Exception as e:
                                update_status = "failed"
                                failure_reason = f"Push dispatch error: {str(e)}"
                                span.http_status = 500
                    
                    elif channel == "in-app":
                        # In-app notifications are typically just database records, no external call needed.
                        # Mark as sent immediately.
                        pass # Status remains 'sent' or 'pending' if it's meant to be read by the app.

                    # Update transaction notification status in DB
                    update_json = {"transactionNotifications": [{
                        "action": 2, # UPDATE
                        "transactionNotificationId": notif_id,
                        "companyId": company_id,
                        "status": update_status,
                        "sentAt": datetime.utcnow().isoformat(),
                        "failureReason": failure_reason
                    }]}
                    update_res = transactionNotifications_sp(update_json)
                    if update_res.status_code != 200:
                        # Log error but try to continue for other notifications
                        print(f"Error updating notification {notif_id}: {update_res.body}")
                        notification["dispatchError"] = json.loads(update_res.body).get("error", "Unknown error")
                    else:
                        notification.update({"status": update_status, "sentAt": datetime.utcnow().isoformat(), "failureReason": failure_reason})

                    results.append(notification)

            return JSONResponse(content={"transactionNotifications": results}, status_code=200)

        except Exception as e:
            return JSONResponse(content={"error": str(e)}, status_code=500)


async def confirm_transactionNotification_connector(payload: dict) -> JSONResponse:
    """
    Marks a transaction notification as confirmed (or failed) based on Stripe webhook data.
    """
    with workflow_step("Confirm Transaction Notifications", workflow_name="transaction_notification_confirm"):
        try:
            company_id          = payload.get("companyId")
            transaction_id      = payload.get("transactionId")
            stripe_reference    = payload.get("stripeReference") # payment_intent.id or payout.id
            movement_type       = payload.get("movementType")
            is_success          = payload.get("isSuccess", False) # From Stripe webhook glue logic
            stripe_failure_reason = payload.get("failureReason")

            if not all([company_id, transaction_id, stripe_reference]):
                return JSONResponse({"error": "companyId, transactionId, and stripeReference are required"}, status_code=400)

            # Step 1: Query for relevant notifications that match this Stripe reference
            query_json = {"transactionNotifications": [{
                "companyId": company_id,
                "transactionId": transaction_id,
                "stripeReference": stripe_reference,
                "movementType": movement_type # Filter by movement type if available
            }]}
            all_notif_res = all_transactionNotifications_sp(query_json)
            if all_notif_res.status_code != 200:
                return all_notif_res # Propagate error

            notifications_to_confirm = json.loads(all_notif_res.body).get("transactionNotifications", [])
            if not notifications_to_confirm:
                return JSONResponse(content={
                    "message": "No matching notifications found for confirmation.",
                    "transactionId": transaction_id,
                    "stripeReference": stripe_reference
                }, status_code=200)

            results = []
            for notification in notifications_to_confirm:
                notif_id = notification.get("transactionNotificationId")
                current_status = notification.get("status")

                new_status = "confirmed" if is_success else "failed"
                failure_reason = stripe_failure_reason if not is_success else None

                # Only update if status needs to change from 'sent' or 'pending'
                if current_status not in [new_status, "failed"]:
                    update_json = {"transactionNotifications": [{
                        "action": 2, # UPDATE
                        "transactionNotificationId": notif_id,
                        "companyId": company_id,
                        "status": new_status,
                        "confirmedAt": datetime.utcnow().isoformat(),
                        "failureReason": failure_reason
                    }]}

                    update_res = transactionNotifications_sp(update_json)
                    if update_res.status_code != 200:
                        print(f"Error confirming notification {notif_id}: {update_res.body}")
                        notification["confirmError"] = json.loads(update_res.body).get("error", "Unknown error")
                    else:
                        notification.update({"status": new_status, "confirmedAt": datetime.utcnow().isoformat(), "failureReason": failure_reason})

                    results.append(notification)
                else:
                    results.append(notification) # Add to results even if not updated
            
            # After confirmation, optionally dispatch a confirmation email/push for 'confirmed' status
            # This can be a separate dispatch, or the original dispatch service can handle status changes.
            # For now, we'll return the updated notifications.

            return JSONResponse(content={"transactionNotifications": results}, status_code=200)

        except Exception as e:
            return JSONResponse(content={"error": str(e)}, status_code=500)
