from fastapi.responses import JSONResponse
from databases import connection
import json
from observability import log_audit, workflow_step


def _sp(payload: dict):
    conn = cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_notificationAudiences] @pjsonfile = %s",
            (json.dumps({"notificationAudiences": [payload]}),)
        )
        row = cursor.fetchone()
        raw = row[0] if row and row[0] else "null"
        return json.loads(raw) if isinstance(raw, str) else raw
    except Exception as e:
        return {"error": str(e)}
    finally:
        try:
            if cursor: cursor.close()
        except Exception: pass
        try:
            if conn: conn.close()
        except Exception: pass


async def notificationAudiences_sp(payload: dict):
    action = payload.get("action", "")
    notification_audience_id = payload.get("notificationAudienceId") # May be None on insert
    company_id = payload.get("companyId", 0)
    push_notification_id = payload.get("pushNotificationId")

    with workflow_step(f"NotificationAudience {action}", workflow_name="NotificationAudienceProcess"):
        result = _sp(payload)

        if isinstance(result, dict) and "error" in result:
            log_audit(
                "notificationAudiences",
                notification_audience_id or push_notification_id, # Use push_notification_id if audience_id not yet known
                "action",
                None,
                action,
                action_type="failed"
            )
            return JSONResponse(content=result, status_code=400)

        # For 'upsert' action, extract the ID from the result if it was an insert/update.
        # Assuming successful upsert returns {'notificationAudiences': [{'notificationAudienceId': X, ...}]}
        # or directly {'notificationAudienceId': X}
        new_notification_audience_id = None
        if isinstance(result, dict):
            if result.get("notificationAudiences") and isinstance(result["notificationAudiences"], list):
                if result["notificationAudiences"][0].get("notificationAudienceId"):
                    new_notification_audience_id = result["notificationAudiences"][0]["notificationAudienceId"]
            elif result.get("notificationAudienceId"):
                new_notification_audience_id = result["notificationAudienceId"]

        if action == "upsert":
            # Log audit for the mutation. Old value is None as we don't fetch before upsert for this pattern.
            log_audit(
                "notificationAudiences",
                new_notification_audience_id or notification_audience_id, # Use new ID if available, else original
                "action",
                None,
                action,
                action_type="upsert"
            )

        return JSONResponse(content=result, status_code=200)
