"""
WorkflowOrchestrator Agent

Routes incoming manufacturing events to the correct agent and manages
the production queue. Also exposes the queue state and machine dashboard.

Events handled:
  new_order       → validate machine availability → insert productionOrder → mark machine in_use
  start_cycle     → update order status to 'running'
  complete_cycle  → trigger CostEngine.complete_order → MaintenancePredictor.analyze_machine
  cancel_order    → free machine
  get_queue       → return active orders with ETA
  get_dashboard   → machines + queue + today KPIs in one call
"""

from fastapi.responses import JSONResponse
from databases import connection
from modules.costEngine import _sp, compute_cycle_cost
from modules.maintenancePredictor import analyze_machine as _analyze_machine
from modules.profitabilityOptimizer import analyze_profitability as _analyze_profit
import json
from datetime import datetime, timezone


def _get_active_orders(company_id: int) -> list:
    result = _sp("sp_productionOrders", {
        "orders": [{"action": "active", "companyId": company_id}]
    })
    return result.get("orders", [])


def _get_machines(company_id: int) -> list:
    result = _sp("sp_machines", {"machines": [{"action": "list", "companyId": company_id}]})
    return result.get("machines", [])


async def create_order(payload: dict):
    """
    POST /manufacturing/queue/create
    Validates machine availability and creates the production order.
    """
    company_id = payload.get("companyId")
    machine_id = payload.get("machineId")

    if not company_id or not machine_id:
        return JSONResponse({"error": "companyId and machineId required"}, 400)

    result = _sp("sp_productionOrders", {"orders": [{"action": "insert", **payload}]})

    if "error" in result:
        return JSONResponse(result, 409)

    return JSONResponse({**result, "status": "queued", "message": "Orden creada y máquina asignada"})


async def start_cycle(payload: dict):
    """POST /manufacturing/queue/start — operator confirms cycle started"""
    order_id = payload.get("orderId")
    if not order_id:
        return JSONResponse({"error": "orderId required"}, 400)

    result = _sp("sp_productionOrders", {"orders": [{"action": "start", "orderId": order_id}]})
    return JSONResponse({**result, "startedAt": datetime.now(timezone.utc).isoformat()})


async def complete_cycle(payload: dict):
    """
    POST /manufacturing/queue/complete
    Calculates real cost via CostEngine, updates order, re-analyzes machine wear.
    """
    order_id = payload.get("orderId")
    machine_id = payload.get("machineId")
    company_id = payload.get("companyId")

    if not all([order_id, machine_id, company_id]):
        return JSONResponse({"error": "orderId, machineId, companyId required"}, 400)

    # Run CostEngine
    detergent_grams = float(payload.get("detergentGrams", 0))
    actual_minutes = payload.get("actualMinutes")
    ticket_price = float(payload.get("ticketPrice", 0))

    cost = compute_cycle_cost(machine_id, company_id, detergent_grams, actual_minutes, ticket_price)

    _sp("sp_productionOrders", {"orders": [{
        "action":               "complete",
        "orderId":              order_id,
        "realCostElec":         cost["realCostElec"],
        "realCostWater":        cost["realCostWater"],
        "realCostDetergent":    cost["realCostDetergent"],
        "realCostLabor":        cost["realCostLabor"],
        "realCostDepreciation": cost["realCostDepreciation"],
        "realCostOverhead":     cost["realCostOverhead"],
        "realCostTotal":        cost["realCostTotal"],
        "ticketPrice":          ticket_price,
        "margin":               cost["margin"],
        "marginPct":            cost["marginPct"],
    }]})

    # Re-analyze wear after cycle
    wear_response = await _analyze_machine({"machineId": machine_id, "companyId": company_id})
    wear_data = json.loads(wear_response.body)

    return JSONResponse({
        "orderId":   order_id,
        "cost":      cost,
        "wear":      wear_data,
        "completed": True,
    })


async def cancel_order(payload: dict):
    """POST /manufacturing/queue/cancel — free machine without cost calculation"""
    order_id = payload.get("orderId")
    machine_id = payload.get("machineId")
    if not order_id:
        return JSONResponse({"error": "orderId required"}, 400)

    _sp("sp_productionOrders", {"orders": [{"action": "update", "orderId": order_id, "status": "cancelled"}]})
    if machine_id:
        _sp("sp_machines", {"machines": [{"action": "update", "machineId": machine_id, "status": "available"}]})

    return JSONResponse({"message": "Orden cancelada, máquina liberada"})


async def get_queue(payload: dict):
    """POST /manufacturing/queue — active orders with ETA"""
    company_id = payload.get("companyId")
    if not company_id:
        return JSONResponse({"error": "companyId required"}, 400)

    orders = _get_active_orders(company_id)
    now = datetime.now(timezone.utc)

    for o in orders:
        started_raw = o.get("startedAt")
        if started_raw and o.get("status") == "running":
            try:
                started = datetime.fromisoformat(started_raw.replace("Z", "+00:00"))
                elapsed = (now - started).seconds // 60
                remaining = max(0, int(o.get("cycleMinutes", 45)) - elapsed)
                o["elapsedMinutes"] = elapsed
                o["remainingMinutes"] = remaining
                o["etaIso"] = (now.replace(microsecond=0).isoformat())
            except Exception:
                pass

    return JSONResponse({"queue": orders, "count": len(orders)})


async def get_dashboard(payload: dict):
    """
    POST /manufacturing/dashboard
    Single call returns machines status + queue + today profitability KPIs.
    """
    company_id = payload.get("companyId")
    if not company_id:
        return JSONResponse({"error": "companyId required"}, 400)

    machines = _get_machines(company_id)
    queue = _get_active_orders(company_id)

    # Today's quick KPIs from profitability (1-day window)
    profit_resp = await _analyze_profit({"companyId": company_id, "periodDays": 1})
    kpis = json.loads(profit_resp.body)

    # Status counts
    status_counts = {}
    for m in machines:
        s = m.get("status", "unknown")
        status_counts[s] = status_counts.get(s, 0) + 1

    return JSONResponse({
        "machines":     machines,
        "queue":        queue,
        "statusCounts": status_counts,
        "todayKpis":    kpis,
    })
