from fastapi.responses import JSONResponse
from databases import connection
from modules.azure_notifications import send_azure_push, register_device_token
import json

# targetType values that can actually be resolved to a recipient list today.
# 'Role' is exposed in the schema/UI but there is no user-role mapping
# anywhere in the database, so it can't be resolved to anyone -- surface
# that clearly instead of guessing. 'Company' IS resolvable via
# users.companyId.
_UNSUPPORTED_TARGET_TYPES = {"Role"}


def _get_active_user_ids(cursor, company_id=None) -> list:
    cursor.execute(
        "EXEC [dbo].[sp_pushNotifications_activeUsers] @pjsonfile = %s",
        (json.dumps({"companyId": company_id}),),
    )
    rows = cursor.fetchall()
    json_result = "".join(row[0] for row in rows if row and row[0])
    if not json_result:
        return []
    return [u["userId"] for u in json.loads(json_result).get("users", [])]


def _record_delivery(cursor, push_notification_id: int, user_id: int, was_sent: bool) -> None:
    cursor.execute(
        "EXEC [dbo].[sp_pushNotifications_recordDelivery] @pjsonfile = %s",
        (json.dumps({
            "pushNotificationId": push_notification_id,
            "userId": user_id,
            "isSent": 1 if was_sent else 0,
        }),),
    )


async def pushNotifications_sp(json_file: dict):
    conn = None
    try:
        print("[pushNotifications][module] Handler started.")
        print("[pushNotifications][module] Payload received:", json_file)

        conn = connection()
        cursor = conn.cursor()

        # SP expects: {"pushNotifications":[{...}]}
        if isinstance(json_file, dict) and isinstance(json_file.get("pushNotifications"), list):
            sp_payload = json_file
            payload_item = sp_payload["pushNotifications"][0] if sp_payload["pushNotifications"] else {}
            print("[pushNotifications][module] Input format detected: wrapped payload.")
            print("[pushNotifications][module] Wrapped payload item count:", len(sp_payload["pushNotifications"]))
        else:
            payload_item = json_file if isinstance(json_file, dict) else {}
            sp_payload = {"pushNotifications": [payload_item]}
            print("[pushNotifications][module] Input format detected: flat payload. Auto-wrapped for SP.")
            print("[pushNotifications][module] Auto-wrapped payload item count: 1")

        payload_json = json.dumps(sp_payload)
        print("[pushNotifications][module] payload_item used for action/Azure logic:", payload_item)
        print("[pushNotifications][module] Executing SP: sp_pushNotifications")
        print("[pushNotifications][module] SP payload JSON:", payload_json)
        cursor.execute("EXEC [dbo].[sp_pushNotifications] @pjsonfile = %s", (payload_json,))

        # Upsert SP returns ONE row, ONE column -- use fetchone()[0]
        row = cursor.fetchone()
        print("[pushNotifications][module] Raw DB row:", row)
        json_result = row[0] if row else '{"message": "ok"}'
        print("[pushNotifications][module] SP json_result:", json_result)

        parsed_content = json.loads(json_result)
        action = payload_item.get("action") if isinstance(payload_item, dict) else None
        print("[pushNotifications][module] action:", action)

        status_value = str(parsed_content.get("status", "")).lower() if isinstance(parsed_content, dict) else ""
        is_success = status_value in {"success", "ok"}
        print("[pushNotifications][module] status_value:", status_value)
        print("[pushNotifications][module] is_success:", is_success)

        if action == 1 and is_success:
            title = payload_item.get("title", "New Notification") if isinstance(payload_item, dict) else "New Notification"
            message = payload_item.get("message", "") if isinstance(payload_item, dict) else ""
            target_type = (payload_item.get("targetType") or "User") if isinstance(payload_item, dict) else "User"
            target_user_id = payload_item.get("targetUserId") if isinstance(payload_item, dict) else None
            target_company_id = payload_item.get("targetCompanyId") if isinstance(payload_item, dict) else None
            push_notification_id = parsed_content.get("pushNotificationId") if isinstance(parsed_content, dict) else None
            push_notification_id = int(push_notification_id) if push_notification_id else None
            print(
                "[pushNotifications][module] action==1 and SP success, preparing Azure push:",
                {"title": title, "message": message, "targetType": target_type,
                 "targetUserId": target_user_id, "targetCompanyId": target_company_id}
            )

            if target_type in _UNSUPPORTED_TARGET_TYPES:
                reason = (
                    f"targetType '{target_type}' is not supported yet: there is no user-role "
                    f"mapping in the database to resolve recipients from."
                )
                print("[pushNotifications][module] Push not sent:", reason)
                parsed_content["pushSendSkipped"] = True
                parsed_content["pushSendReason"] = reason
            elif target_type == "Company" and not target_company_id:
                reason = "targetType 'Company' requires targetCompanyId."
                print("[pushNotifications][module] Push not sent:", reason)
                parsed_content["pushSendSkipped"] = True
                parsed_content["pushSendReason"] = reason
            else:
                if target_type == "All":
                    recipient_ids = _get_active_user_ids(cursor)
                elif target_type == "Company":
                    recipient_ids = _get_active_user_ids(cursor, target_company_id)
                else:
                    recipient_ids = [target_user_id] if target_user_id else []

                print("[pushNotifications][module] Resolved recipients:", recipient_ids)
                sent_count = 0
                for user_id in recipient_ids:
                    try:
                        azure_result = await send_azure_push(title, message, user_id)
                        was_sent = bool(isinstance(azure_result, dict) and azure_result.get("sent") is True)
                        if was_sent:
                            sent_count += 1
                            print("[pushNotifications][module] Azure push sent successfully.",
                                  {"userId": user_id, "results": azure_result.get("results")})
                        else:
                            print("[pushNotifications][module] Azure push skipped/unsent.",
                                  {"userId": user_id, "reason": azure_result.get("reason") if isinstance(azure_result, dict) else None})
                    except Exception as azure_error:
                        was_sent = False
                        print("[pushNotifications][module] Azure push failed:", {"userId": user_id, "error": str(azure_error)})

                    if push_notification_id:
                        _record_delivery(cursor, push_notification_id, user_id, was_sent)

                parsed_content["pushSendSkipped"] = False
                parsed_content["pushRecipientCount"] = len(recipient_ids)
                parsed_content["pushSentCount"] = sent_count
        elif action == 1:
            print(
                "[pushNotifications][module] action==1 but SP status is not success; skipping Azure push.",
                {"status": parsed_content.get("status") if isinstance(parsed_content, dict) else None}
            )

        elif action is None:
            print("[pushNotifications][module] action is missing/None; Azure push not evaluated.")
        else:
            print("[pushNotifications][module] action is not 1; Azure push not required.", {"action": action})

        print("[pushNotifications][module] Returning parsed response:", parsed_content)
        return JSONResponse(content=parsed_content, status_code=200)
    except Exception as e:
        print("[pushNotifications][module] Exception raised:", str(e))
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
            print("[pushNotifications][module] DB connection closed.")


def all_pushNotifications_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_pushNotifications_all] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        # SQL Server may split large FOR JSON output across multiple rows -- always join.
        # Guard against None cells and empty tables (empty table is NOT an error).
        json_result = "".join(row[0] for row in rows if row and row[0])
        if not json_result:
            return JSONResponse(content={"pushNotifications": []}, status_code=200)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


async def register_device_sp(json_file: dict):
    try:
        print("[pushNotifications][registerDevice] Handler started.")
        print("[pushNotifications][registerDevice] Payload received:", json_file)

        user_id = json_file.get("userId") if isinstance(json_file, dict) else None
        token = json_file.get("token") if isinstance(json_file, dict) else None
        platform = json_file.get("platform") if isinstance(json_file, dict) else None

        if user_id is None or token is None or platform is None:
            return JSONResponse(
                content={
                    "status": "error",
                    "message": "Missing required fields: userId, token, platform",
                },
                status_code=400,
            )

        result = await register_device_token(user_id=user_id, token=token, platform=platform)

        if result.get("success"):
            return JSONResponse(
                content={
                    "status": "success",
                    "message": "Device registered successfully.",
                    "installationId": result.get("installationId"),
                },
                status_code=200,
            )

        status_code = result.get("status_code") or 500
        if status_code < 400:
            status_code = 500

        return JSONResponse(
            content={
                "status": "error",
                "message": "Device registration failed.",
                "reason": result.get("reason"),
                "details": result.get("response_text") or result.get("error"),
            },
            status_code=status_code,
        )
    except Exception as e:
        print("[pushNotifications][registerDevice] Exception raised:", str(e))
        return JSONResponse(content={"error": str(e)}, status_code=500)


def one_pushNotifications_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_pushNotifications_one] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows if row and row[0])
        if not json_result:
            return JSONResponse(content={"pushNotifications": []}, status_code=200)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
