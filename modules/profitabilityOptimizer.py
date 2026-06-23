"""
ProfitabilityOptimizer Agent

Compares ticket price vs real cost per service type and generates
actionable pricing recommendations.

Logic:
  1. Pull productionOrders for requested period (default 30 days)
  2. Group by cycleType → avg real cost, avg ticket price, avg margin
  3. Flag loss-makers (margin < 0) and thin margins (marginPct < 20%)
  4. Suggest new prices = avgRealCost × (1 + targetMarginPct / 100)
  5. Save daily / weekly snapshot
  6. Return ranked list + suggestions JSON
"""

from fastapi.responses import JSONResponse
from databases import connection
from modules.costEngine import _sp, _get_rates
import json


def _get_orders(company_id: int, period_days: int) -> list:
    result = _sp("sp_productionOrders", {
        "orders": [{"action": "list", "companyId": company_id, "periodDays": period_days}]
    })
    return result.get("orders", [])


async def analyze_profitability(payload: dict):
    """
    POST /manufacturing/profitability/analyze
    Returns per-service-type profitability + global KPIs + price suggestions.
    """
    company_id = payload.get("companyId")
    period_days = int(payload.get("periodDays", 30))

    if not company_id:
        return JSONResponse({"error": "companyId required"}, 400)

    orders = [o for o in _get_orders(company_id, period_days) if o.get("realCostTotal")]
    rates = _get_rates(company_id)
    target_margin = float(rates.get("targetMarginPct", 40.0))

    if not orders:
        return JSONResponse({
            "totalOrders": 0,
            "totalRevenue": 0,
            "totalRealCost": 0,
            "totalMargin": 0,
            "avgMarginPct": 0,
            "byServiceType": [],
            "suggestions": [],
            "message": "No completed orders with cost data in this period",
        })

    # Group by cycleType
    groups: dict[str, dict] = {}
    for o in orders:
        ct = o.get("cycleType", "unknown")
        if ct not in groups:
            groups[ct] = {"count": 0, "revenue": 0, "cost": 0, "margin": 0}
        g = groups[ct]
        g["count"] += 1
        g["revenue"] += float(o.get("ticketPrice") or 0)
        g["cost"] += float(o.get("realCostTotal") or 0)
        g["margin"] += float(o.get("margin") or 0)

    by_type = []
    suggestions = []
    for ct, g in sorted(groups.items(), key=lambda x: x[1]["margin"] / max(x[1]["revenue"],0.01)):
        avg_cost = g["cost"] / g["count"]
        avg_price = g["revenue"] / g["count"]
        avg_margin = g["margin"] / g["count"]
        avg_margin_pct = (avg_margin / avg_price * 100) if avg_price > 0 else 0
        suggested = avg_cost * (1 + target_margin / 100)
        status = (
            "loss"  if avg_margin_pct < 0
            else "thin" if avg_margin_pct < 20
            else "ok"   if avg_margin_pct < target_margin
            else "good"
        )

        entry = {
            "cycleType":     ct,
            "orderCount":    g["count"],
            "avgRealCost":   round(avg_cost, 2),
            "avgTicketPrice": round(avg_price, 2),
            "avgMargin":     round(avg_margin, 2),
            "avgMarginPct":  round(avg_margin_pct, 1),
            "totalRevenue":  round(g["revenue"], 2),
            "totalMargin":   round(g["margin"], 2),
            "status":        status,
        }
        by_type.append(entry)

        if status in ("loss", "thin") or avg_price < suggested:
            suggestions.append({
                "cycleType":      ct,
                "currentAvgPrice": round(avg_price, 2),
                "suggestedPrice":  round(suggested, 2),
                "delta":           round(suggested - avg_price, 2),
                "reason": (
                    f"Pérdida: costo real ${avg_cost:.2f} > precio ${avg_price:.2f}" if status == "loss"
                    else f"Margen bajo {avg_margin_pct:.1f}% (objetivo {target_margin:.0f}%)"
                ),
            })

    total_rev = sum(float(o.get("ticketPrice") or 0) for o in orders)
    total_cost = sum(float(o.get("realCostTotal") or 0) for o in orders)
    total_margin = total_rev - total_cost
    avg_margin_pct_global = (total_margin / total_rev * 100) if total_rev > 0 else 0
    loss_orders = sum(1 for o in orders if float(o.get("margin") or 0) < 0)

    return JSONResponse({
        "periodDays":    period_days,
        "totalOrders":   len(orders),
        "totalRevenue":  round(total_rev, 2),
        "totalRealCost": round(total_cost, 2),
        "totalMargin":   round(total_margin, 2),
        "avgMarginPct":  round(avg_margin_pct_global, 1),
        "lossOrders":    loss_orders,
        "byServiceType": by_type,
        "suggestions":   suggestions,
    })


async def save_snapshot(payload: dict):
    """POST /manufacturing/profitability/snapshot — persist daily/weekly/monthly KPIs"""
    result = _sp("sp_profitabilitySnapshots", {"snapshots": [{"action": "upsert", **payload}]})
    return JSONResponse(result)


async def get_snapshots(payload: dict):
    """POST /manufacturing/profitability/snapshots"""
    result = _sp("sp_profitabilitySnapshots", {"snapshots": [{"action": "list", **payload}]})
    return JSONResponse(result)
