"""
Loan Offer Reminders — daily scan

While a lender has capital published in the P2P marketplace, borrowers only
heard about it ONCE (the push fired at publish time). This job re-announces
the active offers on a schedule so borrowers who missed or ignored the
original push keep seeing that money is available.

Reads through sp_loanOffers_all (same SP the /all_loanOffers endpoint uses),
filters expired/empty offers, and sends ONE consolidated company push per run
— never one push per offer, so a lender republishing can't spam borrowers.
Skips silently when the company has no live offers.
"""

import json
from datetime import datetime, timezone

from fastapi.responses import JSONResponse

from modules.loanOffers import all_loan_offers_sp
from modules.pushNotifications import pushNotifications_sp


def _active_offers(company_id: int) -> list:
    """Live offers for the company: isActive, not expired, capital > 0."""
    response = all_loan_offers_sp({"loanOffers": [{"companyId": company_id, "isActive": True}]})
    try:
        offers = json.loads(response.body).get("loanOffers", [])
    except Exception as e:
        print(f"[offerReminders] failed to parse offers: {e}")
        return []

    now = datetime.now(timezone.utc)
    live = []
    for o in offers:
        if not o.get("isActive") or float(o.get("availableCapital") or 0) <= 0:
            continue
        expires_at = o.get("expiresAt")
        if expires_at:
            try:
                exp = datetime.fromisoformat(str(expires_at).replace("Z", "+00:00"))
                if exp.tzinfo is None:
                    exp = exp.replace(tzinfo=timezone.utc)
                if exp < now:
                    continue
            except ValueError:
                pass  # unparseable expiry — treat as non-expiring
        live.append(o)
    return live


async def check_active_offers(payload: dict):
    company_id = int(payload.get("companyId", 0))
    dry_run = bool(payload.get("dryRun", False))
    if not company_id:
        return JSONResponse({"error": "companyId required"}, status_code=400)

    offers = _active_offers(company_id)
    if not offers:
        return JSONResponse({"dryRun": dry_run, "sent": False, "reason": "no active offers"}, status_code=200)

    total_capital = sum(float(o.get("availableCapital") or 0) for o in offers)
    min_rate = min(float(o.get("minRate") or 0) for o in offers)
    capital_txt = f"${total_capital:,.2f}"

    title = "💰 Capital disponible para préstamo"
    message = (
        f"Hay {capital_txt} disponibles en el marketplace a tasas desde "
        f"{min_rate:g}% anual. Envía tu solicitud hoy."
    )

    if dry_run:
        return JSONResponse({
            "dryRun": True, "sent": False, "offers": len(offers),
            "totalCapital": total_capital, "title": title, "message": message,
        }, status_code=200)

    try:
        await pushNotifications_sp({
            "pushNotifications": [{
                "action": 1,
                "companyId": company_id,
                "title": title,
                "message": message,
                "notificationType": "Info",
                "priority": "High",
                "targetType": "Company",
                "targetCompanyId": company_id,
                "navigationRoute": "/p2p-lending",
                "payloadJson": json.dumps({
                    "type": "LoanOfferReminder",
                    "offers": len(offers),
                    "totalCapital": total_capital,
                }),
            }]
        })
    except Exception as e:
        print(f"[offerReminders] push failed for companyId={company_id}: {e}")
        return JSONResponse({"dryRun": False, "sent": False, "error": str(e)}, status_code=500)

    print(f"[offerReminders] sent for companyId={company_id}: {len(offers)} offers, {capital_txt}")
    return JSONResponse({
        "dryRun": False, "sent": True, "offers": len(offers), "totalCapital": total_capital,
    }, status_code=200)
