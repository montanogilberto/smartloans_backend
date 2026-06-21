# Push Notifications Documentation

This document describes all push-notification-related backend functionality currently implemented in this project.

## Overview

Push notification data is managed through three API endpoints exposed by FastAPI and backed by SQL Server stored procedures.

### Main files involved

- `routes_/pushNotification.py`
  - Declares API endpoints.
  - Loads endpoint descriptions from `docs_description/*.txt`.
- `modules/pushNotifications.py`
  - Implements DB calls and JSON response handling.
  - Integrates Azure push dispatch for insert action flow.
  - Uses `connection()` from `databases.py`.
- `modules/azure_notifications.py`
  - Builds and sends Azure Notification Hub requests.
  - Handles missing/invalid config checks and returns structured send results.
- `docs_description/pushNotifications.txt`
- `docs_description/pushNotifications_all.txt`
- `docs_description/pushNotifications_one.txt`

## Endpoints

All current push-notification endpoints use **POST**.

---

### 1) `/pushNotifications`

**Purpose**  
Performs INSERT, UPDATE, or DELETE on push notifications via stored procedure:

```sql
EXEC [dbo].[sp_pushNotifications] @pjsonfile = <json>
```

**Route definition**  
File: `routes_/pushNotification.py`

```python
@router.post("/pushNotifications", summary="pushNotifications CRUD", description=pushNotifications_docstring)
async def pushNotifications(json: dict):
    return await pushNotifications_sp(json)
```

**Handler function (current behavior)**  
File: `modules/pushNotifications.py`

```python
async def pushNotifications_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()

        # Accepts both wrapped and flat payload formats
        # Wrapped: {"pushNotifications":[{...}]}
        # Flat: {...} -> auto-wrapped for SP
        if isinstance(json_file, dict) and isinstance(json_file.get("pushNotifications"), list):
            sp_payload = json_file
            payload_item = sp_payload["pushNotifications"][0] if sp_payload["pushNotifications"] else {}
        else:
            payload_item = json_file if isinstance(json_file, dict) else {}
            sp_payload = {"pushNotifications": [payload_item]}

        cursor.execute("EXEC [dbo].[sp_pushNotifications] @pjsonfile = %s", (json.dumps(sp_payload),))
        row = cursor.fetchone()
        json_result = row[0] if row else '{"message": "ok"}'
        parsed_content = json.loads(json_result)

        action = payload_item.get("action") if isinstance(payload_item, dict) else None
        status_value = str(parsed_content.get("status", "")).lower() if isinstance(parsed_content, dict) else ""
        is_success = status_value in {"success", "ok"}

        # Azure push integration:
        # Only when action==1 and SP reports success
        if action == 1 and is_success:
            title = payload_item.get("title", "New Notification")
            message = payload_item.get("message", "")
            target_user_id = payload_item.get("targetUserId")
            azure_result = await send_azure_push(title, message, target_user_id)

            # Logging is based on structured result:
            # sent / skipped-unsent / legacy fallback
            ...
        return JSONResponse(content=parsed_content, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
```

**Example request**

```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/pushNotifications" \
  -H "Content-Type: application/json" \
  -d '{
    "action":1,
    "companyId":1,
    "title":"Welcome!",
    "message":"This is your first notification.",
    "notificationType":"Info",
    "priority":"Normal",
    "targetType":"User",
    "targetUserId":123,
    "isRead":false,
    "isSent":false
  }'
```

---

### 2) `/all_pushNotifications`

**Purpose**  
Returns all push-notification records for a company via stored procedure:

```sql
EXEC [dbo].[sp_pushNotifications_all] @pjsonfile = <json>
```

**Route definition**

```python
@router.post("/all_pushNotifications", summary="all pushNotifications", description=pushNotifications_all_docstring)
def all_pushNotifications(json: dict):
    return all_pushNotifications_sp(json)
```

**Handler behavior**
- Executes SP.
- Calls `fetchall()`.
- Joins potentially split JSON chunks into one string.
- Returns empty array payload when no data.

```python
def all_pushNotifications_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_pushNotifications_all] @pjsonfile = %s", (json.dumps(json_file),))
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
```

**Example request**

```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/all_pushNotifications" \
  -H "Content-Type: application/json" \
  -d '{"pushNotifications":[{"companyId":1}]}'
```

---

### 3) `/one_pushNotification`

**Purpose**  
Returns one push-notification record by primary key via stored procedure:

```sql
EXEC [dbo].[sp_pushNotifications_one] @pjsonfile = <json>
```

**Route definition**

```python
@router.post("/one_pushNotification", summary="one pushNotification", description=pushNotifications_one_docstring)
def one_pushNotification(json: dict):
    return one_pushNotifications_sp(json)
```

**Handler behavior**
- Executes SP.
- Joins JSON fragments from SQL result rows.
- Returns empty array payload if not found / no JSON output.

```python
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
```

**Example request**

```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/one_pushNotification" \
  -H "Content-Type: application/json" \
  -d '{"companyId":1,"pushNotificationId":1}'
```

---

## Azure Notification Hub Integration

Azure push is triggered from `modules/pushNotifications.py` only when:

- `action == 1` (insert path), and
- Stored procedure response status is success-like (`success` / `ok`).

### Azure sender function

File: `modules/azure_notifications.py`

`send_azure_push(title, message, target_user_id)` now returns a **structured result**:

- Missing env configuration:
  - `{"sent": False, "reason": "missing_config", "status_code": None}`
- Invalid parsed connection-string parts:
  - `{"sent": False, "reason": "invalid_connection_string", "status_code": None}`
- Azure HTTP response received:
  - `{"sent": True, "reason": "ok", "status_code": <2xx>, "response_text": "..."}`
  - `{"sent": False, "reason": "azure_non_success_status", "status_code": <non-2xx>, "response_text": "..."}`

Required environment variables:

- `AZURE_NOTIFICATION_HUB_CONNECTION_STRING`
- `AZURE_NOTIFICATION_HUB_NAME`
- `AZURE_NOTIFICATION_HUB_FORMAT` (optional, default: `fcm`, legacy option: `gcm`)

### Targeted Delivery Requirement (Important)

Setting `ServiceBusNotification-Tags: user_<id>` only works if the mobile device is registered in Azure Notification Hub with the same tag.

Example installation/registration tag set:

```json
{
  "installationId": "device-installation-id",
  "pushChannel": "fcm_device_token",
  "tags": ["user_123"]
}
```

If registrations/installations are missing or tags do not match, Azure may return success while delivering to `0` devices.

### Push module logging semantics (updated)

`modules/pushNotifications.py` logs based on structured Azure result:

- Success:
  - `[pushNotifications][module] Azure push sent successfully. {'status_code': ...}`
- Skipped/unsent:
  - `[pushNotifications][module] Azure push skipped/unsent. {'reason': 'missing_config'|'invalid_connection_string'|'azure_non_success_status', 'status_code': ...}`
- Exception path:
  - `[pushNotifications][module] Azure push failed: <error>`

This prevents false-positive success logs when Azure push is skipped.

## Request/Response Behavior Summary

### Success responses
- HTTP `200`
- JSON payload returned from the stored procedure output.
- For list/single queries with no data:
  - returns `{"pushNotifications": []}`

### Error responses
- HTTP `500`
- JSON payload format:
  ```json
  {
    "error": "<exception message>"
  }
  ```

## Data Flow

1. Client sends JSON request to one of the three routes.
2. Route function delegates to corresponding function in `modules/pushNotifications.py`.
3. Module function:
   - opens DB connection
   - normalizes payload shape for SP (`wrapped` or auto-wrapped from `flat`)
   - executes stored procedure with `@pjsonfile`
   - parses returned JSON text
   - for insert-success flow (`action==1` + SP success), attempts Azure push
   - logs Azure outcome using structured result
   - wraps response with FastAPI `JSONResponse`
4. Connection is closed in `finally`.

## Latest Verified Log Sample

Validated log output for missing Azure configuration case:

```text
[pushNotifications][module] action: 1
[pushNotifications][module] status_value: success
[pushNotifications][module] is_success: True
[pushNotifications][module] action==1 and SP success, preparing Azure push: {'title': 'Welcome!', 'message': 'This is your first notification.', 'targetUserId': 123}
[azure_notifications] send_azure_push called. {'title': 'Welcome!', 'message_length': 32, 'target_user_id': 123}
[azure_notifications] Missing AZURE_NOTIFICATION_HUB_CONNECTION_STRING or AZURE_NOTIFICATION_HUB_NAME. Skipping push.
[pushNotifications][module] Azure push skipped/unsent. {'reason': 'missing_config', 'status_code': None}
[pushNotifications][module] Returning parsed response: {'status': 'success', 'message': 'PushNotification(s) inserted successfully.', 'pushNotificationId': '4'}
[pushNotifications][module] DB connection closed.
[pushNotifications][route] Outgoing response prepared.
```

Interpretation:
- Stored procedure succeeded.
- Azure push was skipped due to missing config.
- Logging is now accurate (`skipped/unsent`) and no longer reports false success.

## Notes for Maintenance

- Current implementation is database-driven: request schema is effectively controlled by SQL stored procedures.
- `all` and `one` handlers explicitly handle SQL Server JSON chunking by concatenating rows.
- Endpoint documentation shown in Swagger/OpenAPI is loaded from:
  - `docs_description/pushNotifications.txt`
  - `docs_description/pushNotifications_all.txt`
  - `docs_description/pushNotifications_one.txt`

## Troubleshooting / Dependency Compatibility

During runtime startup, an environment dependency mismatch was observed:

- Error signature:
  - `ImportError: cannot import name 'Proxy' from 'httpx'`
- Cause:
  - incompatible `openai` and `httpx` versions loaded in Python environment.
- Known-good pair used during recovery:
  - `openai==1.13.3`
  - `httpx==0.27.2`

Recommendation:
- Pin these versions in deployment/runtime environments to prevent drift-related startup failures.
- Ensure the application runs with the intended project virtual environment interpreter.

## Operational Checklist (Push Notifications)

Use this checklist when validating push notifications in QA/UAT/production diagnostics:

1. **Environment/Startup**
   - Confirm app starts without import/runtime dependency errors.
   - Confirm expected venv interpreter is used.

2. **Database-level test**
   - Execute `sp_pushNotifications` directly with a known-good payload.
   - Verify success JSON is returned and `pushNotificationId` is generated.

3. **API-level test**
   - Call `POST /pushNotifications` with equivalent payload.
   - Verify response status/body.
   - If API fails while DB succeeds, investigate:
     - `companyId` validity in application context
     - tenant/company scoping rules
     - payload transformation differences between API and direct SP call

4. **Azure integration checks**
   - Missing Azure env vars -> expect `skipped/unsent` with `missing_config`.
   - Invalid connection string parts -> expect `skipped/unsent` with `invalid_connection_string`.
   - Azure non-2xx response -> expect `skipped/unsent` with `azure_non_success_status`.
   - Azure exception -> expect `Azure push failed` log.

5. **Read-back verification**
   - Validate inserted record via:
     - `POST /all_pushNotifications`
     - `POST /one_pushNotification`

6. **Error-path checks**
   - Invalid `companyId`
   - Missing required fields (`action`, `companyId`, `title`, etc.)
   - type mismatches (`isRead`/`isSent`, ID fields)

## Related Files (Quick Reference)

- `routes_/pushNotification.py`
- `modules/pushNotifications.py`
- `modules/azure_notifications.py`
- `docs_description/pushNotifications.txt`
- `docs_description/pushNotifications_all.txt`
- `docs_description/pushNotifications_one.txt`
- `databases.py` (shared DB connection utility)
