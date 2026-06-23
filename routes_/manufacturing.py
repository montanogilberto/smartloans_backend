"""
Manufacturing Module Routes

All endpoints are under /manufacturing prefix.

WorkflowOrchestrator  → /manufacturing/queue/*   /manufacturing/dashboard
CostEngine            → /manufacturing/cost-engine/*
MaintenancePredictor  → /manufacturing/maintenance/*
ProfitabilityOptimizer→ /manufacturing/profitability/*
AlertDispatcher       → /manufacturing/alerts/*
Machines CRUD         → /manufacturing/machines/*
"""
from fastapi import APIRouter

from modules.workflowOrchestrator import (
    create_order, start_cycle, complete_cycle, cancel_order,
    get_queue, get_dashboard,
)
from modules.costEngine import (
    calculate_cost, complete_order as cost_complete_order,
    get_utility_rates, upsert_utility_rates,
)
from modules.maintenancePredictor import (
    analyze_machine, analyze_all_machines,
    log_maintenance, get_maintenance_history,
)
from modules.profitabilityOptimizer import (
    analyze_profitability, save_snapshot, get_snapshots,
)
from modules.alertDispatcher import (
    notify_cycle_done, notify_maintenance_needed,
    notify_low_margin, notify_low_supply,
)
from modules.costEngine import _sp

router = APIRouter(prefix="/manufacturing", tags=["Manufacturing"])


# ── Dashboard ─────────────────────────────────────────────────────────────────

@router.post("/dashboard", summary="Full dashboard: machines + queue + today KPIs")
async def dashboard(payload: dict):
    return await get_dashboard(payload)


# ── Machines CRUD ─────────────────────────────────────────────────────────────

@router.post("/machines", summary="Create a machine")
async def create_machine(payload: dict):
    result = _sp("sp_machines", {"machines": [{"action": "insert", **payload}]})
    from fastapi.responses import JSONResponse
    return JSONResponse(result)


@router.post("/machines/list", summary="List all machines for a company")
async def list_machines(payload: dict):
    result = _sp("sp_machines", {"machines": [{"action": "list", **payload}]})
    from fastapi.responses import JSONResponse
    return JSONResponse(result)


@router.post("/machines/update", summary="Update machine fields")
async def update_machine(payload: dict):
    result = _sp("sp_machines", {"machines": [{"action": "update", **payload}]})
    from fastapi.responses import JSONResponse
    return JSONResponse(result)


# ── Queue / WorkflowOrchestrator ──────────────────────────────────────────────

@router.post("/queue", summary="Get active production queue with ETAs")
async def queue(payload: dict):
    return await get_queue(payload)


@router.post("/queue/create", summary="Create a production order (validates machine availability)")
async def queue_create(payload: dict):
    return await create_order(payload)


@router.post("/queue/start", summary="Mark cycle as started")
async def queue_start(payload: dict):
    return await start_cycle(payload)


@router.post("/queue/complete", summary="Complete cycle: calculate real cost + update wear")
async def queue_complete(payload: dict):
    return await complete_cycle(payload)


@router.post("/queue/cancel", summary="Cancel order and free machine")
async def queue_cancel(payload: dict):
    return await cancel_order(payload)


@router.post("/queue/history", summary="Completed orders (last N days)")
async def queue_history(payload: dict):
    result = _sp("sp_productionOrders", {"orders": [{"action": "list", **payload}]})
    from fastapi.responses import JSONResponse
    return JSONResponse(result)


# ── CostEngine ────────────────────────────────────────────────────────────────

@router.post("/cost-engine/calculate", summary="Calculate real wash cost without saving")
async def cost_calculate(payload: dict):
    return await calculate_cost(payload)


@router.post("/cost-engine/complete", summary="Calculate cost + save to order")
async def cost_complete(payload: dict):
    return await cost_complete_order(payload)


@router.post("/cost-engine/rates", summary="Get current utility rates")
async def rates_get(payload: dict):
    return await get_utility_rates(payload)


@router.post("/cost-engine/rates/save", summary="Create or update utility rates")
async def rates_save(payload: dict):
    return await upsert_utility_rates(payload)


# ── MaintenancePredictor ──────────────────────────────────────────────────────

@router.post("/maintenance/analyze", summary="Analyze wear for one machine")
async def maintenance_analyze(payload: dict):
    return await analyze_machine(payload)


@router.post("/maintenance/analyze-all", summary="Analyze wear for all company machines")
async def maintenance_analyze_all(payload: dict):
    return await analyze_all_machines(payload)


@router.post("/maintenance/log", summary="Record completed maintenance service")
async def maintenance_log(payload: dict):
    return await log_maintenance(payload)


@router.post("/maintenance/history", summary="Get maintenance log history")
async def maintenance_history(payload: dict):
    return await get_maintenance_history(payload)


# ── ProfitabilityOptimizer ────────────────────────────────────────────────────

@router.post("/profitability/analyze", summary="Analyze margins by service type + price suggestions")
async def profitability_analyze(payload: dict):
    return await analyze_profitability(payload)


@router.post("/profitability/snapshot", summary="Save periodic profitability snapshot")
async def profitability_snapshot(payload: dict):
    return await save_snapshot(payload)


@router.post("/profitability/snapshots", summary="Get profitability snapshot history")
async def profitability_snapshots(payload: dict):
    return await get_snapshots(payload)


# ── AlertDispatcher ───────────────────────────────────────────────────────────

@router.post("/alerts/cycle-done", summary="Notify client: cycle complete (Push + WhatsApp)")
async def alert_cycle_done(payload: dict):
    return await notify_cycle_done(payload)


@router.post("/alerts/maintenance", summary="Notify manager: machine needs maintenance")
async def alert_maintenance(payload: dict):
    return await notify_maintenance_needed(payload)


@router.post("/alerts/low-margin", summary="Notify manager: order closed with low/negative margin")
async def alert_low_margin(payload: dict):
    return await notify_low_margin(payload)


@router.post("/alerts/low-supply", summary="Notify manager: supply running low")
async def alert_low_supply(payload: dict):
    return await notify_low_supply(payload)
