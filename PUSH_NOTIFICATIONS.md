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
  - Uses `connection()` from `databases.py`.
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
def pushNotifications(json: dict):
    return pushNotifications_sp(json)
```

**Handler function**  
File: `modules/pushNotifications.py`

```python
def pushNotifications_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_pushNotifications] @pjsonfile = %s", (json.dumps(json_file),))
        row = cursor.fetchone()
        json_result = row[0] if row else '{"message": "ok"}'
        return JSONResponse(content=json.loads(json_result), status_code=200)
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
   - executes stored procedure with `@pjsonfile`
   - parses returned JSON text
   - wraps response with FastAPI `JSONResponse`
4. Connection is closed in `finally`.

## Notes for Maintenance

- Current implementation is database-driven: request schema is effectively controlled by SQL stored procedures.
- `all` and `one` handlers explicitly handle SQL Server JSON chunking by concatenating rows.
- Endpoint documentation shown in Swagger/OpenAPI is loaded from:
  - `docs_description/pushNotifications.txt`
  - `docs_description/pushNotifications_all.txt`
  - `docs_description/pushNotifications_one.txt`

## Related Files (Quick Reference)

- `routes_/pushNotification.py`
- `modules/pushNotifications.py`
- `docs_description/pushNotifications.txt`
- `docs_description/pushNotifications_all.txt`
- `docs_description/pushNotifications_one.txt`
- `databases.py` (shared DB connection utility)
