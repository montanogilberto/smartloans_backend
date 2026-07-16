"""
Onboarding Completion Reminders — daily scan

Checks every client's progress across the non-trivial onboarding steps
(Código QR, ID document capture, biometric verification, contract/pagaré
acceptance, payment account setup) and sends ONE consolidated push
notification reminder to anyone with something incomplete. Each client is
only ever reminded once automatically — enforced by sp_onboardingReminders'
UNIQUE constraint on (clientId, companyId) — to avoid repeat nagging; staff
can still manually finish or nudge a client through the wizard at any time.

All persistence goes through sp_onboardingReminders (@pjsonfile convention,
same as every other module) — this module only computes which steps are
missing from the flags the SP returns, and triggers the notification.
"""

import json
from databases import connection
from fastapi.responses import JSONResponse
from modules.pushNotifications import pushNotifications_sp


def _conn():
    return connection()


def _sp_onboarding_reminders(payload: dict) -> dict:
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_onboardingReminders] @pjsonfile = %s",
            (json.dumps({"onboardingReminders": [payload]}),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        print(f"[onboardingReminders] SP error: {e}")
        return {}
    finally:
        if conn:
            conn.close()


async def check_onboarding_completeness(payload: dict):
    company_id = int(payload.get("companyId", 0))
    dry_run = bool(payload.get("dryRun", False))
    if not company_id:
        return JSONResponse({"error": "companyId required"}, status_code=400)

    result = _sp_onboarding_reminders({"action": "getIncomplete", "companyId": company_id})
    clients = result.get("clients", []) if isinstance(result, dict) else []

    reminded = []
    complete = 0

    for c in clients:
        client_id = c.get("clientId")

        missing = []
        if not c.get("hasQr"):
            missing.append("Código QR")
        if not c.get("hasDocuments"):
            missing.append("Documento de identidad")
        if not c.get("isVerified"):
            missing.append("Verificación biométrica")
        if not c.get("hasContract"):
            missing.append("Contrato y pagaré")
        if not c.get("hasBankAccount") or not c.get("hasSavedCard"):
            missing.append("Cuenta de pagos (bancaria y tarjeta)")

        if not missing:
            complete += 1
            continue

        missing_text = ", ".join(missing)

        if dry_run:
            reminded.append({"clientId": client_id, "missing": missing})
            continue

        try:
            await pushNotifications_sp({
                "pushNotifications": [{
                    "action": 1,
                    "companyId": company_id,
                    "title": "⚠️ Completa tu registro",
                    "message": f"Aún te falta: {missing_text}. Complétalo para poder recibir o pagar un préstamo.",
                    "notificationType": "Warning",
                    "priority": "High",
                    "targetType": "User",
                    "targetUserId": client_id,
                    "navigationRoute": "/clients",
                    "payloadJson": json.dumps({"type": "OnboardingReminder", "clientId": client_id, "missing": missing}),
                }]
            })
            _sp_onboarding_reminders({
                "action": "markReminded",
                "clientId": client_id,
                "companyId": company_id,
                "missingSteps": missing_text,
            })
            reminded.append({"clientId": client_id, "missing": missing})
        except Exception as e:
            print(f"[onboardingReminders] failed for clientId={client_id}: {e}")

    return JSONResponse({
        "dryRun": dry_run,
        "reminded": len(reminded),
        "complete": complete,
        "total": len(clients),
        "details": reminded,
    }, status_code=200)
