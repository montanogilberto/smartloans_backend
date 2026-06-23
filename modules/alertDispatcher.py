"""
AlertDispatcher Agent

Fires Push / SMS / WhatsApp at the right manufacturing moments:

  CYCLE_DONE      → Push to client: "Tu ropa está lista"
                  → WhatsApp to client with ticket summary
  ORDER_READY     → SMS + Push to staff
  MAINTENANCE     → Push to manager when machine wear >= 85
  LOW_SUPPLY      → Push to manager (triggered by caller, threshold configurable)
  COST_ALERT      → Push to manager when margin < 0

Reuses existing pushNotifications + whatsapp modules.
"""

from fastapi.responses import JSONResponse
from databases import connection
from modules.costEngine import _sp
import json


def _send_push(company_id: int, client_id: int | None, title: str, body: str, data: dict = None) -> dict:
    payload = {
        "pushNotifications": [{
            "action":    1,
            "companyId": company_id,
            "clientId":  client_id,
            "title":     title,
            "body":      body,
            "data":      json.dumps(data or {}),
            "channel":   "manufacturing",
        }]
    }
    return _sp("sp_pushNotifications", payload)


def _send_whatsapp(phone: str, message: str) -> dict:
    conn = None
    try:
        from databases import connection as _connection
        conn = _connection()
        cur = conn.cursor()
        cur.execute(
            "EXEC [dbo].[sp_whatsapp] @pjsonfile = %s",
            (json.dumps({"whatsapp": [{"action": 1, "phone": phone, "message": message}]}),)
        )
        row = cur.fetchone()
        conn.commit()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        return {"error": str(e), "whatsapp": "skipped"}
    finally:
        if conn:
            try: conn.close()
            except: pass


async def notify_cycle_done(payload: dict):
    """
    POST /manufacturing/alerts/cycle-done
    Sends Push + optional WhatsApp when a wash cycle completes.

    Body: { companyId, orderId, clientId, clientPhone?, machineName,
            cycleType, ticketPrice, realCostTotal, margin }
    """
    company_id   = payload.get("companyId")
    order_id     = payload.get("orderId")
    client_id    = payload.get("clientId")
    machine_name = payload.get("machineName", "Máquina")
    cycle_type   = payload.get("cycleType", "")
    ticket_price = payload.get("ticketPrice", 0)
    phone        = payload.get("clientPhone")

    push_result = _send_push(
        company_id, client_id,
        title="🧺 ¡Tu ropa está lista!",
        body=f"{machine_name} terminó tu ciclo {cycle_type}. Puedes pasar a recogerla.",
        data={"orderId": order_id, "type": "cycle_done"},
    )

    wa_result = {}
    if phone:
        msg = (
            f"✅ *Tu ropa está lista*\n"
            f"Máquina: {machine_name}\n"
            f"Servicio: {cycle_type}\n"
            f"Total: ${ticket_price:.2f} MXN\n"
            f"¡Pasa a recogerla cuando gustes!"
        )
        wa_result = _send_whatsapp(phone, msg)

    # Mark alert sent on order
    _sp("sp_productionOrders", {"orders": [{"action": "alert_sent", "orderId": order_id}]})

    return JSONResponse({"push": push_result, "whatsapp": wa_result, "alertSent": True})


async def notify_maintenance_needed(payload: dict):
    """
    POST /manufacturing/alerts/maintenance
    Sends Push to manager when machine wear >= threshold.

    Body: { companyId, managerId, machineId, machineName, wearScore,
            remainingCycles, recommendation }
    """
    company_id     = payload.get("companyId")
    manager_id     = payload.get("managerId")
    machine_name   = payload.get("machineName", "Máquina")
    wear_score     = payload.get("wearScore", 0)
    remaining      = payload.get("remainingCycles", 0)
    recommendation = payload.get("recommendation", "")
    urgent         = int(wear_score) >= 95

    push_result = _send_push(
        company_id, manager_id,
        title=f"{'🚨 URGENTE' if urgent else '⚠️'} Mantenimiento: {machine_name}",
        body=f"Desgaste {wear_score}%. {recommendation}",
        data={"type": "maintenance", "machineId": payload.get("machineId"), "wearScore": wear_score},
    )
    return JSONResponse({"push": push_result, "urgent": urgent})


async def notify_low_margin(payload: dict):
    """
    POST /manufacturing/alerts/low-margin
    Sends Push to manager when an order closes with negative or thin margin.

    Body: { companyId, managerId, orderId, cycleType, ticketPrice,
            realCostTotal, margin, marginPct }
    """
    company_id  = payload.get("companyId")
    manager_id  = payload.get("managerId")
    order_id    = payload.get("orderId")
    cycle_type  = payload.get("cycleType", "")
    ticket_price = float(payload.get("ticketPrice", 0))
    real_cost   = float(payload.get("realCostTotal", 0))
    margin      = float(payload.get("margin", 0))
    margin_pct  = float(payload.get("marginPct", 0))
    is_loss     = margin < 0

    push_result = _send_push(
        company_id, manager_id,
        title=f"{'❌ Venta con pérdida' if is_loss else '⚠️ Margen bajo'} — {cycle_type}",
        body=(
            f"Orden #{order_id}: precio ${ticket_price:.2f} vs costo ${real_cost:.2f} "
            f"({'pérdida' if is_loss else 'margen'} {margin_pct:.1f}%)"
        ),
        data={"type": "low_margin", "orderId": order_id, "marginPct": margin_pct},
    )
    return JSONResponse({"push": push_result, "isLoss": is_loss})


async def notify_low_supply(payload: dict):
    """
    POST /manufacturing/alerts/low-supply
    Body: { companyId, managerId, supplyName, currentLevel, unit }
    """
    company_id   = payload.get("companyId")
    manager_id   = payload.get("managerId")
    supply_name  = payload.get("supplyName", "Insumo")
    current      = payload.get("currentLevel", 0)
    unit         = payload.get("unit", "kg")

    push_result = _send_push(
        company_id, manager_id,
        title=f"⚠️ Insumo bajo: {supply_name}",
        body=f"Quedan {current} {unit} de {supply_name}. Favor de reabastecer.",
        data={"type": "low_supply", "supply": supply_name},
    )
    return JSONResponse({"push": push_result})
