from fastapi.responses import JSONResponse
from databases import connection
from modules.azure_notifications import send_azure_push, register_device_token
import json


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
            target_user_id = payload_item.get("targetUserId") if isinstance(payload_item, dict) else None
            print(
                "[pushNotifications][module] action==1 and SP success, preparing Azure push:",
                {"title": title, "message": message, "targetUserId": target_user_id}
            )
            try:
                azure_result = await send_azure_push(title, message, target_user_id)

                if isinstance(azure_result, dict):
                    if azure_result.get("sent") is True:
                        print("[pushNotifications][module] Azure push sent successfully.",
                              {"results": azure_result.get("results")})
                    else:
                        print("[pushNotifications][module] Azure push skipped/unsent.",
                              {"reason": azure_result.get("reason"),
                               "results": azure_result.get("results")})
            except Exception as azure_error:
                print("[pushNotifications][module] Azure push failed:", str(azure_error))
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
