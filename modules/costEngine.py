"""
CostEngine Agent — Real Wash Cost Calculator

Formula per cycle:
  electricity  = machine.kwhPerCycle  × rates.electricityPerKwh
  water        = machine.litersPerCycle × rates.waterPerLiter
  detergent    = order.detergentGrams × rates.detergentPerGram
  labor        = (order.actualMinutes or machine.cycleMinutes) / 60 × rates.laborPerHour
  depreciation = machine.purchaseCost / machine.lifetimeCycles
  subtotal     = electricity + water + detergent + labor + depreciation
  overhead     = subtotal × (rates.overheadPct / 100)
  real_cost    = subtotal + overhead

  margin    = ticketPrice - real_cost
  marginPct = (margin / ticketPrice) × 100   (0 if ticketPrice == 0)
  suggestPrice = real_cost × (1 + rates.targetMarginPct / 100)
"""

from fastapi.responses import JSONResponse
from databases import connection
import json


def _conn():
    return connection()


def _sp(proc: str, payload: dict):
    conn = None
    try:
        conn = _conn()
        cur = conn.cursor()
        cur.execute(f"EXEC [dbo].[{proc}] @pjsonfile = %s", (json.dumps(payload),))
        row = cur.fetchone()
        conn.commit()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        return {"error": str(e)}
    finally:
        if conn:
            try: conn.close()
            except: pass


def _get_machine(machine_id: int) -> dict:
    result = _sp("sp_machines", {"machines": [{"action": "one", "machineId": machine_id}]})
    return result if result and "error" not in result else {}


def _get_rates(company_id: int) -> dict:
    result = _sp("sp_utilityRates", {"rates": [{"action": "get", "companyId": company_id}]})
    return result if result and "error" not in result else {
        "electricityPerKwh": 3.20,
        "waterPerLiter": 0.015,
        "detergentPerGram": 0.08,
        "laborPerHour": 80.0,
        "overheadPct": 15.0,
        "targetMarginPct": 40.0,
    }


def compute_cycle_cost(
    machine_id: int,
    company_id: int,
    detergent_grams: float,
    actual_minutes: float | None,
    ticket_price: float,
) -> dict:
    """
    Pure cost calculation. Returns breakdown dict.
    Does NOT write to DB — caller decides whether to persist.
    """
    machine = _get_machine(machine_id)
    rates = _get_rates(company_id)

    kwh = float(machine.get("kwhPerCycle", 0))
    liters = float(machine.get("litersPerCycle", 0))
    cycle_mins = float(actual_minutes or machine.get("cycleMinutes", 45))
    purchase = float(machine.get("purchaseCost", 0))
    lifetime = float(machine.get("lifetimeCycles", 5000)) or 5000

    elec = kwh * float(rates.get("electricityPerKwh", 3.20))
    water = liters * float(rates.get("waterPerLiter", 0.015))
    det = float(detergent_grams) * float(rates.get("detergentPerGram", 0.08))
    labor = (cycle_mins / 60.0) * float(rates.get("laborPerHour", 80.0))
    depreciation = purchase / lifetime
    subtotal = elec + water + det + labor + depreciation
    overhead = subtotal * (float(rates.get("overheadPct", 15.0)) / 100.0)
    real_cost = subtotal + overhead

    margin = ticket_price - real_cost
    margin_pct = (margin / ticket_price * 100) if ticket_price > 0 else 0
    suggest_price = real_cost * (1 + float(rates.get("targetMarginPct", 40.0)) / 100.0)

    return {
        "realCostElec":         round(elec, 4),
        "realCostWater":        round(water, 4),
        "realCostDetergent":    round(det, 4),
        "realCostLabor":        round(labor, 4),
        "realCostDepreciation": round(depreciation, 4),
        "realCostOverhead":     round(overhead, 4),
        "realCostTotal":        round(real_cost, 4),
        "ticketPrice":          ticket_price,
        "margin":               round(margin, 4),
        "marginPct":            round(margin_pct, 2),
        "suggestedPrice":       round(suggest_price, 2),
        "breakdown": {
            "electricity":   f"{kwh} kWh × ${rates.get('electricityPerKwh')} = ${elec:.4f}",
            "water":         f"{liters} L × ${rates.get('waterPerLiter')} = ${water:.4f}",
            "detergent":     f"{detergent_grams}g × ${rates.get('detergentPerGram')} = ${det:.4f}",
            "labor":         f"{cycle_mins:.0f} min × ${rates.get('laborPerHour')}/h = ${labor:.4f}",
            "depreciation":  f"${purchase} ÷ {int(lifetime)} cycles = ${depreciation:.4f}",
            "overhead":      f"{rates.get('overheadPct')}% of ${subtotal:.4f} = ${overhead:.4f}",
        }
    }


async def calculate_cost(payload: dict):
    """POST /manufacturing/cost-engine/calculate"""
    machine_id = payload.get("machineId")
    company_id = payload.get("companyId")
    detergent_grams = float(payload.get("detergentGrams", 0))
    actual_minutes = payload.get("actualMinutes")
    ticket_price = float(payload.get("ticketPrice", 0))

    if not machine_id or not company_id:
        return JSONResponse({"error": "machineId and companyId required"}, 400)

    result = compute_cycle_cost(machine_id, company_id, detergent_grams, actual_minutes, ticket_price)
    return JSONResponse(result)


async def complete_order(payload: dict):
    """
    POST /manufacturing/cost-engine/complete
    Calculates real cost, saves to productionOrder, increments machine cycles.
    """
    order_id = payload.get("orderId")
    machine_id = payload.get("machineId")
    company_id = payload.get("companyId")
    detergent_grams = float(payload.get("detergentGrams", 0))
    actual_minutes = payload.get("actualMinutes")
    ticket_price = float(payload.get("ticketPrice", 0))

    if not all([order_id, machine_id, company_id]):
        return JSONResponse({"error": "orderId, machineId, companyId required"}, 400)

    cost = compute_cycle_cost(machine_id, company_id, detergent_grams, actual_minutes, ticket_price)

    result = _sp("sp_productionOrders", {"orders": [{
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

    return JSONResponse({**cost, **result})


async def get_utility_rates(payload: dict):
    """GET current utility rates for a company"""
    company_id = payload.get("companyId")
    if not company_id:
        return JSONResponse({"error": "companyId required"}, 400)
    rates = _get_rates(company_id)
    return JSONResponse(rates)


async def upsert_utility_rates(payload: dict):
    """Save or update utility rates"""
    result = _sp("sp_utilityRates", {"rates": [{"action": "upsert", **payload}]})
    return JSONResponse(result)
