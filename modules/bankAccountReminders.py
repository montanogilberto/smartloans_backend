"""
Bank Account (CLABE) Reminders — daily scan

A verified borrower without a linked bank account is the exact gap that
blocks disbursement at accept time (the lender flow requires a verified
CLABE or Stripe account before money moves). The one-shot onboarding
reminder mentions it once and never again; this job keeps inviting the
clients who remain KYC-verified but bank-less, so they can actually receive
a loan by SPEI (sin comisiones) the day a proposal is accepted.

Reuses sp_onboardingReminders' getIncomplete listing (it already computes
hasBankAccount/isVerified per client) — no new SP. One push per client per
run, deep-linked to the payments tab where the CLABE is linked.
"""

import json

from fastapi.responses import JSONResponse

from modules.onboardingReminders import _sp_onboarding_reminders
from modules.pushNotifications import pushNotifications_sp


async def check_missing_bank_accounts(payload: dict):
    company_id = int(payload.get("companyId", 0))
    dry_run = bool(payload.get("dryRun", False))
    if not company_id:
        return JSONResponse({"error": "companyId required"}, status_code=400)

    result = _sp_onboarding_reminders({"action": "getIncomplete", "companyId": company_id})
    clients = result.get("clients", []) if isinstance(result, dict) else []

    # Only clients who finished KYC but never linked a CLABE — they can act
    # on the push immediately, and they're the ones a disbursement would block on.
    targets = [c for c in clients if c.get("isVerified") and not c.get("hasBankAccount")]

    if dry_run:
        return JSONResponse({
            "dryRun": True, "sent": 0,
            "targets": [c.get("clientId") for c in targets],
        }, status_code=200)

    sent = []
    for c in targets:
        client_id = c.get("clientId")
        try:
            await pushNotifications_sp({
                "pushNotifications": [{
                    "action": 1,
                    "companyId": company_id,
                    "title": "🏦 Vincula tu cuenta bancaria",
                    "message": "Registra tu CLABE para recibir tu préstamo por SPEI sin comisiones. Solo toma un minuto.",
                    "notificationType": "Info",
                    "priority": "High",
                    "targetType": "User",
                    "targetUserId": client_id,
                    "navigationRoute": f"/client-dashboard/{client_id}?tab=payments",
                    "payloadJson": json.dumps({"type": "BankAccountReminder", "clientId": client_id}),
                }]
            })
            sent.append(client_id)
        except Exception as e:
            print(f"[bankAccountReminders] failed for clientId={client_id}: {e}")

    print(f"[bankAccountReminders] companyId={company_id}: reminded {len(sent)}/{len(targets)}")
    return JSONResponse({"dryRun": False, "sent": len(sent), "clientIds": sent}, status_code=200)
