"""
Registration Completion Reminders — daily scan

CreateAccount.tsx's 4-step wizard (Cuenta/Perfil/Verificar/Acceso) can be
abandoned partway through. This scans dbo.users for anyone with an
incomplete registration (sp_registrationReminders' 'getIncomplete' action
already excludes anyone previously reminded — enforced by its UNIQUE(userId)
constraint, same "remind once" guarantee as onboardingReminders.py) and
sends ONE reminder each:

  - email, always, if we have one
  - the first of push / WhatsApp / SMS that actually goes through, to
    cellphone — push is tried first but a mid-registration user rarely has
    a device token registered yet (that only happens post-login), so this
    realistically resolves to WhatsApp, falling back to SMS if that fails.

All persistence goes through sp_registrationReminders (@pjsonfile
convention, same as every other module) — this module only computes what's
missing and drives the notification channels.
"""

import json
import logging
from databases import connection
from fastapi.responses import JSONResponse
from modules.pushNotifications import pushNotifications_sp
from modules.users import _send_email, _send_sms_message

logger = logging.getLogger("registrationReminders")

_STEP_LABELS = {
    "hasProfile": "Perfil de aplicación",
    "isVerified": "Verificación de identidad",
    "hasAccess":  "Rol y empresa (Acceso)",
}


def _conn():
    return connection()


def _sp_registration_reminders(payload: dict) -> dict:
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_registrationReminders] @pjsonfile = %s",
            (json.dumps({"registrationReminders": [payload]}),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        logger.exception("[registrationReminders] SP error: %s", e)
        return {}
    finally:
        if conn:
            conn.close()


async def _notify_cellphone(user_id: int, company_id, cellphone: str, message: str) -> str:
    """push -> WhatsApp -> SMS, first one that actually sends. Returns the
    channel used, or '' if there's no cellphone or every channel failed."""
    if not cellphone:
        return ""

    try:
        push_payload = {
            "action": 1,
            "title": "⚠️ Completa tu registro",
            "message": message,
            "notificationType": "Warning",
            "priority": "High",
            "targetType": "User",
            "targetUserId": user_id,
            "navigationRoute": "/create-account",
            "payloadJson": json.dumps({"type": "RegistrationReminder", "userId": user_id}),
        }
        if company_id:
            push_payload["companyId"] = company_id
        push_response = await pushNotifications_sp({"pushNotifications": [push_payload]})
        push_body = json.loads(push_response.body)
        if push_body.get("pushSentCount", 0) > 0:
            return "push"
    except Exception as e:
        logger.warning("[registrationReminders] push attempt failed for userId=%s: %s", user_id, e)

    try:
        _send_sms_message(cellphone, message, via_whatsapp=True)
        return "whatsapp"
    except Exception as e:
        logger.warning("[registrationReminders] whatsapp attempt failed for userId=%s: %s", user_id, e)

    try:
        _send_sms_message(cellphone, message, via_whatsapp=False)
        return "sms"
    except Exception as e:
        logger.warning("[registrationReminders] sms attempt failed for userId=%s: %s", user_id, e)

    return ""


async def check_registration_completeness(payload: dict):
    dry_run = bool(payload.get("dryRun", False))

    result = _sp_registration_reminders({"action": "getIncomplete"})
    users = result.get("users", []) if isinstance(result, dict) else []

    reminded = []

    for u in users:
        user_id = u.get("userId")

        missing = [label for key, label in _STEP_LABELS.items() if not u.get(key)]
        if not missing:
            continue

        missing_text = ", ".join(missing)
        message = f"Aún te falta: {missing_text}. Completa tu registro para acceder al sistema."

        if dry_run:
            reminded.append({"userId": user_id, "missing": missing})
            continue

        email = u.get("email")
        if email:
            try:
                _send_email(email, "Completa tu registro", message)
            except Exception as e:
                logger.warning("[registrationReminders] email failed for userId=%s: %s", user_id, e)

        channel_used = await _notify_cellphone(user_id, u.get("companyId"), u.get("cellphone"), message)

        _sp_registration_reminders({
            "action": "markReminded",
            "userId": user_id,
            "missingSteps": missing_text,
        })
        reminded.append({"userId": user_id, "missing": missing, "channel": channel_used})

    return JSONResponse({
        "dryRun": dry_run,
        "reminded": len(reminded),
        "total": len(users),
        "details": reminded,
    }, status_code=200)
