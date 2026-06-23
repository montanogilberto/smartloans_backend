"""
MaintenancePredictor Agent

Tracks machine wear and predicts when service is needed.

Wear score (0–100):
  base            = (cyclesSinceLastMaintenance / maintenanceEvery) × 70
  lifetime_factor = (currentCycleCount / lifetimeCycles) × 30
  wear_score      = min(100, base + lifetime_factor)

When wear_score >= 85 → trigger maintenance alert
When wear_score >= 95 → force machine to 'maintenance' status
"""

from fastapi.responses import JSONResponse
from databases import connection
from modules.costEngine import _sp
import json
import math


def _compute_wear(
    cycles_since_maintenance: int,
    maintenance_every: int,
    current_cycle_count: int,
    lifetime_cycles: int,
) -> int:
    maintenance_every = maintenance_every or 200
    lifetime_cycles = lifetime_cycles or 5000
    base = (cycles_since_maintenance / maintenance_every) * 70
    lifetime_factor = (current_cycle_count / lifetime_cycles) * 30
    return min(100, math.floor(base + lifetime_factor))


def _predict_remaining_cycles(
    current_cycle_count: int,
    last_maintenance_cycle: int,
    maintenance_every: int,
) -> int:
    next_service = last_maintenance_cycle + maintenance_every
    return max(0, next_service - current_cycle_count)


async def analyze_machine(payload: dict):
    """
    POST /manufacturing/maintenance/analyze
    Computes wear score for one machine, updates DB, returns prediction.
    """
    machine_id = payload.get("machineId")
    company_id = payload.get("companyId")

    if not machine_id or not company_id:
        return JSONResponse({"error": "machineId and companyId required"}, 400)

    machine = _sp("sp_machines", {"machines": [{"action": "one", "machineId": machine_id}]})
    if not machine or "error" in machine:
        return JSONResponse({"error": "Machine not found"}, 404)

    current = int(machine.get("currentCycleCount", 0))
    last_maint = int(machine.get("lastMaintenanceCycle", 0))
    maint_every = int(machine.get("maintenanceEvery", 200))
    lifetime = int(machine.get("lifetimeCycles", 5000))
    cycles_since = current - last_maint

    wear = _compute_wear(cycles_since, maint_every, current, lifetime)
    remaining = _predict_remaining_cycles(current, last_maint, maint_every)

    needs_maintenance = wear >= 85
    force_maintenance = wear >= 95

    new_status = None
    if force_maintenance and machine.get("status") == "available":
        new_status = "maintenance"

    _sp("sp_machines", {"machines": [{
        "action":    "update",
        "machineId": machine_id,
        "wearScore": wear,
        **({"status": new_status} if new_status else {}),
    }]})

    return JSONResponse({
        "machineId":           machine_id,
        "machineName":         machine.get("name"),
        "currentCycleCount":   current,
        "cyclesSinceLastMaint": cycles_since,
        "maintenanceEvery":    maint_every,
        "wearScore":           wear,
        "remainingCycles":     remaining,
        "needsMaintenance":    needs_maintenance,
        "forcedToMaintenance": force_maintenance,
        "lifetimePct":         round(current / lifetime * 100, 1),
        "recommendation": (
            "Mantenimiento urgente requerido — máquina fuera de servicio" if force_maintenance
            else "Programar mantenimiento pronto" if needs_maintenance
            else f"OK — {remaining} ciclos para próximo servicio"
        ),
    })


async def analyze_all_machines(payload: dict):
    """
    POST /manufacturing/maintenance/analyze-all
    Runs wear analysis for every machine in the company.
    """
    company_id = payload.get("companyId")
    if not company_id:
        return JSONResponse({"error": "companyId required"}, 400)

    result = _sp("sp_machines", {"machines": [{"action": "list", "companyId": company_id}]})
    machines = result.get("machines", [])

    analyses = []
    for m in machines:
        r = await analyze_machine({"machineId": m["machineId"], "companyId": company_id})
        analyses.append(json.loads(r.body))

    alerts = [a for a in analyses if a.get("needsMaintenance")]
    return JSONResponse({
        "total":          len(analyses),
        "needingService": len(alerts),
        "machines":       analyses,
        "alerts":         alerts,
    })


async def log_maintenance(payload: dict):
    """
    POST /manufacturing/maintenance/log
    Records completed maintenance and resets machine wear score.
    """
    result = _sp("sp_maintenanceLogs", {"logs": [{"action": "insert", **payload}]})
    return JSONResponse(result)


async def get_maintenance_history(payload: dict):
    """POST /manufacturing/maintenance/history"""
    result = _sp("sp_maintenanceLogs", {"logs": [{"action": "list", **payload}]})
    return JSONResponse(result)
