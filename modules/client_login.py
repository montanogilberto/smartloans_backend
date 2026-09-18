"""
Client self-service login (SMS one-time code) — module Contabilidad-adjacent
cousin: a dbo.clients row created at POS checkout (name + phone only) has no
dbo.users row and therefore no way to authenticate at all today. This gives
that client a login path without a password, and auto-provisions the linked
dbo.users/dbo.userCompanies rows on first successful verification.

Deliberately separate from modules/users.py's send_verification_code/verify_code
pair (in-memory, used to re-verify an EXISTING account's identity) -- this is
a different trust model (persisted, phone-is-the-identity, may create a user)
and mixing the two would blur what each one guarantees.
"""
import json
import random
import string
from datetime import datetime, timedelta
from fastapi.responses import JSONResponse
from databases import connection
from observability import log_workflow_step

from modules.users import _normalize_phone, _send_sms_otp, _users_sp_raw, one_users_sp


def _client_login_codes_sp(payload: dict) -> dict:
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_clientLoginCodes @pjsonfile = %s", (json.dumps(payload),))
        row = cursor.fetchone()
        if not row or not row[0]:
            return {"result": [{"error": "1", "msg": "No result from sp_clientLoginCodes"}]}
        return json.loads(row[0])
    finally:
        if conn:
            conn.close()


def send_client_login_code(json_file: dict) -> JSONResponse:
    try:
        payload = (json_file.get("clientLoginCodes") or [{}])[0]
        raw_phone = str(payload.get("phone") or "").strip()
        if not raw_phone:
            return JSONResponse(content={"error": "phone is required"}, status_code=400)
        phone = _normalize_phone(raw_phone)

        conn = connection()
        cursor = conn.cursor()
        cursor.execute("SELECT TOP 1 clientId FROM dbo.clients WHERE cellphone = %s", (phone,))
        found = cursor.fetchone()
        conn.close()
        if not found:
            return JSONResponse(content={"found": False}, status_code=200)

        code = "".join(random.choices(string.digits, k=6))
        expires_at = (datetime.utcnow() + timedelta(minutes=10)).isoformat()

        result = _client_login_codes_sp({
            "clientLoginCodes": [{"action": 1, "phone": phone, "code": code, "expiresAt": expires_at}]
        })
        first = (result.get("result") or [{}])[0]
        if str(first.get("error") or "") == "1":
            return JSONResponse(content={"error": first.get("msg") or "No se pudo generar el código"}, status_code=500)

        _send_sms_otp(phone, code)

        log_workflow_step(
            "Client Login Code Sent", workflow_name="client_login",
            action="SEND", status="SUCCESS", entity="clientLoginCodes",
        )
        return JSONResponse(content={"found": True, "message": "Código enviado"}, status_code=200)
    except Exception as e:
        log_workflow_step(
            "Client Login Code Send Error", workflow_name="client_login",
            status="FAILED", message=str(e),
        )
        return JSONResponse(content={"error": str(e)}, status_code=500)


def verify_client_login_code(json_file: dict) -> JSONResponse:
    try:
        payload = (json_file.get("clientLoginCodes") or [{}])[0]
        raw_phone = str(payload.get("phone") or "").strip()
        code = str(payload.get("code") or "").strip()
        if not raw_phone or not code:
            return JSONResponse(content={"valid": False, "error": "phone y code son requeridos"}, status_code=400)
        phone = _normalize_phone(raw_phone)

        result = _client_login_codes_sp({
            "clientLoginCodes": [{"action": 2, "phone": phone, "code": code}]
        })
        first = (result.get("result") or [{}])[0]
        if str(first.get("error") or "") == "1":
            return JSONResponse(content={"valid": False, "error": first.get("msg")}, status_code=200)

        client = first.get("client") or {}
        client_id = client.get("clientId")
        company_id = client.get("companyId")
        first_name = client.get("first_name") or ""
        last_name = client.get("last_name") or ""
        existing_user_id = client.get("existingUserId")

        if existing_user_id:
            user_id = existing_user_id
        else:
            # Auto-provision. action=1 alone never touches userCompanies
            # (confirmed in sql/sp_users.sql) -- a follow-up action=2 call is
            # required to actually assign companyId/role. Username is
            # deterministic and guaranteed-unique (clientId already is) since
            # this account is never typed in -- it only ever logs in via OTP,
            # so no password is set (NULL), which also means it can never
            # authenticate through the ordinary /login username+password path.
            create_result = _users_sp_raw({
                "users": [{"action": 1, "name": f"client_{client_id}", "cellphone": phone, "clientId": client_id}]
            })
            if str(create_result.get("error") or "") not in (None, "", "0"):
                return JSONResponse(content={"valid": False, "error": "No se pudo crear la cuenta."}, status_code=500)
            user_id = create_result.get("userId")

        _users_sp_raw({
            "users": [{
                "action": 2, "user_id": user_id, "companyId": company_id,
                "roleCode": "pos", "identityVerified": 1,
            }]
        })

        # sp_users_one already selects u.password -- reused here (not a new
        # raw query) just to know whether the client has ever set one, so
        # the frontend can gate the first-login "create a password" step.
        snapshot = json.loads(one_users_sp({"users": [{"userId": user_id}]}).body)
        snapshot_users = snapshot.get("users") or []
        has_password = bool(snapshot_users and snapshot_users[0].get("password"))

        log_workflow_step(
            "Client Login Verified", workflow_name="client_login",
            action="VERIFY", status="SUCCESS", entity="users",
            entity_id=int(user_id) if str(user_id or "").isdigit() else None,
        )

        return JSONResponse(content={
            "valid": True,
            "userId": user_id,
            "companyId": company_id,
            "clientId": client_id,
            "roleCode": "pos",
            "roleName": "Cliente",
            "firstName": first_name,
            "lastName": last_name,
            "hasPassword": has_password,
        }, status_code=200)
    except Exception as e:
        log_workflow_step(
            "Client Login Verify Error", workflow_name="client_login",
            status="FAILED", message=str(e),
        )
        return JSONResponse(content={"valid": False, "error": str(e)}, status_code=500)


def set_client_password(json_file: dict) -> JSONResponse:
    """First-login onboarding step: client sets a password after verifying
    their OTP. Reuses sp_users action=2 (same UPDATE branch already called
    above for companyId/roleCode) -- no new SP, dbo.users.password already
    exists and is varchar(50), same storage as staff passwords today."""
    try:
        payload = (json_file.get("setClientPassword") or [{}])[0]
        user_id = payload.get("userId")
        password = str(payload.get("password") or "").strip()
        if not user_id:
            return JSONResponse(content={"success": False, "error": "userId es requerido"}, status_code=400)
        if len(password) < 6 or len(password) > 50:
            return JSONResponse(
                content={"success": False, "error": "La contraseña debe tener entre 6 y 50 caracteres"},
                status_code=400,
            )

        result = _users_sp_raw({"users": [{"action": 2, "user_id": user_id, "password": password}]})
        if str(result.get("error") or "") not in (None, "", "0"):
            return JSONResponse(content={"success": False, "error": "No se pudo guardar la contraseña"}, status_code=500)

        log_workflow_step(
            "Client Password Set", workflow_name="client_login",
            action="UPDATE", status="SUCCESS", entity="users",
            entity_id=int(user_id) if str(user_id or "").isdigit() else None,
        )
        return JSONResponse(content={"success": True}, status_code=200)
    except Exception as e:
        log_workflow_step(
            "Client Password Set Error", workflow_name="client_login",
            status="FAILED", message=str(e),
        )
        return JSONResponse(content={"success": False, "error": str(e)}, status_code=500)
