"""
rewardBenefits — los puntos de recompensa valen en el prestamo.

POR QUE ESTA MONEDA SI PUEDE VALER: los puntos se ganan por CONDUCTA (pagar a
tiempo, completar expediente, referir), no por azar. Las fichas del arcade se
ganan jugando, y darles valor las convertiria en premio — apuesta + premio es
justo lo que dispara el permiso SEGOB.

LA REGLA QUE NO SE ROMPE: fichas -> puntos NO EXISTE. No hay funcion aqui que
lo haga y no debe agregarse; ese puente convertiria una ganancia de azar en
valor economico.

El incentivo apunta al lado correcto: pagar puntual abarata el credito. Al
reves —que jugar mejorara el credito— empujaria a un cliente endeudado a
apostar para salir del hoyo.
"""

import json
from datetime import datetime, timezone

from fastapi.responses import JSONResponse

from databases import connection
from observability import log_audit, log_workflow_step

WORKFLOW = "rewards"


def _exec_sp(sp_name: str, payload: dict) -> dict:
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{sp_name}] @pjsonfile = %s", (json.dumps(payload),))
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    finally:
        if conn:
            conn.close()


def _first(json_file: dict, key: str) -> dict:
    items = json_file.get(key) or [{}]
    return items[0] if isinstance(items, list) and items else {}


def _rule(company_id: int, rule_type: str) -> dict:
    """Regla activa de ese tipo. La tasa vive en la base, no en el codigo."""
    try:
        conn = connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT TOP 1 ruleId, pointsPerUnit, maxPointsPerTx FROM rewardRules "
            "WHERE companyId = %s AND ruleType = %s AND isActive = 1 ORDER BY ruleId",
            (company_id, rule_type),
        )
        row = cur.fetchone()
        conn.close()
        if not row:
            return {}
        return {"ruleId": row[0], "pointsPerUnit": float(row[1]), "maxPointsPerTx": row[2]}
    except Exception as e:
        print(f"[rewards] no se pudo leer la regla {rule_type}: {type(e).__name__}: {e}")
        return {}


# ---------------------------------------------------------------------------
# Otorgar puntos por conducta
# ---------------------------------------------------------------------------

def _installment_is_on_time(installment_id: int) -> tuple:
    """
    (puntual, monto) de la cuota, leidos de la base.

    La puntualidad se decide AQUI y no en cada sitio que marca pagado: el pago
    manual ni siquiera carga dueDate en su consulta, y repartir esta regla por
    tres lugares es garantia de que alguno quede distinto.
    """
    conn = None
    try:
        conn = connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT TOP 1 dueDate, amount, paidAt FROM loanInstallments WHERE installmentId = %s",
            (installment_id,),
        )
        row = cur.fetchone()
        if not row:
            return False, 0.0
        due, amount, paid_at = row[0], float(row[1] or 0), row[2]
        if due is None:
            return False, amount
        # Sin paidAt todavia, se toma "ahora": el hook corre justo al marcar.
        paid_date = (paid_at or datetime.now(timezone.utc)).date() if hasattr(paid_at or datetime.now(timezone.utc), "date") else None
        due_date = due.date() if hasattr(due, "date") else due
        if paid_date is None or due_date is None:
            return False, amount
        return paid_date <= due_date, amount
    except Exception as e:
        print(f"[rewards] no se pudo leer la cuota {installment_id}: {type(e).__name__}: {e}")
        return False, 0.0
    finally:
        if conn:
            conn.close()


def award_on_time_payment(company_id: int, client_id: int, installment_id: int,
                          amount_mxn: float = None) -> dict:
    """
    Puntos por pagar una cuota A TIEMPO.

    Best-effort e IDEMPOTENTE: una cuota se marca pagada desde varios sitios
    (SPEI manual, cobro automatico) y cualquiera puede reintentar, asi que la
    referencia 'cuota:{id}' garantiza que se otorgue una sola vez. Un fallo
    aqui NUNCA debe tumbar el pago: el dinero ya se movio.
    """
    try:
        on_time, db_amount = _installment_is_on_time(installment_id)
        if not on_time:
            return {"status": "skipped", "reason": "late"}
        amount_mxn = db_amount if amount_mxn is None else amount_mxn
        rule = _rule(company_id, "loan_on_time")
        if not rule:
            return {"status": "skipped", "reason": "no_rule"}

        points = int(amount_mxn * rule["pointsPerUnit"])
        cap = rule.get("maxPointsPerTx")
        if cap:
            points = min(points, int(cap))

        result = _exec_sp("sp_rewards_earnOnce", {"rewards": [{
            "companyId": company_id,
            "clientId": client_id,
            "points": points,
            "ruleId": rule["ruleId"],
            "referenceId": f"cuota:{installment_id}",
            "description": f"Pago puntual de cuota #{installment_id}",
        }]})

        if result.get("status") == "earned":
            log_workflow_step(
                "Reward Points Earned", workflow_name=WORKFLOW, action="loan_on_time",
                entity="rewardPoints", entity_id=client_id,
                message=f"+{points} pts por cuota {installment_id}",
            )
        return result
    except Exception as e:
        print(f"[rewards] no se pudieron otorgar puntos de la cuota {installment_id}: "
              f"{type(e).__name__}: {e}")
        return {"error": str(e)}


def award_simple(company_id: int, client_id: int, rule_type: str,
                 reference_id: str, description: str) -> dict:
    """Puntos de monto fijo (expediente completo, referido activado)."""
    try:
        rule = _rule(company_id, rule_type)
        if not rule:
            return {"status": "skipped", "reason": "no_rule"}
        points = int(rule.get("maxPointsPerTx") or rule["pointsPerUnit"])
        return _exec_sp("sp_rewards_earnOnce", {"rewards": [{
            "companyId": company_id, "clientId": client_id, "points": points,
            "ruleId": rule["ruleId"], "referenceId": reference_id,
            "description": description,
        }]})
    except Exception as e:
        print(f"[rewards] {rule_type} fallo: {type(e).__name__}: {e}")
        return {"error": str(e)}


# ---------------------------------------------------------------------------
# Beneficios
# ---------------------------------------------------------------------------

def reward_benefits_all_sp(json_file: dict):
    """Catalogo de beneficios con si al cliente le alcanzan los puntos."""
    try:
        data = _exec_sp("sp_rewardBenefits_all", json_file)
        if "error" in data:
            return JSONResponse(content=data, status_code=500)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def reward_benefit_reserve_sp(json_file: dict):
    """
    Canjea puntos y aparta un beneficio para el proximo prestamo.

    Se aparta y no se aplica directo porque el prestamo todavia no existe: el
    cliente elige el descuento ANTES de solicitar, y se amarra al credito
    cuando se crea.
    """
    body = _first(json_file, "rewardBenefits")
    try:
        data = _exec_sp("sp_rewardBenefits_reserve", json_file)
        code = data.get("error")
        if code:
            status = 409 if code in ("insufficient_points", "benefit_already_reserved") else 400
            return JSONResponse(content=data, status_code=status)

        log_workflow_step(
            "Reward Benefit Reserved", workflow_name=WORKFLOW, action=data.get("benefitKey"),
            entity="loanRewardBenefits", entity_id=data.get("id"),
            message=f"-{data.get('pointsSpent')} pts",
        )
        log_audit("loanRewardBenefits", data.get("id"), "status", None, "reserved", action="INSERT")
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        print(f"[rewards] reserve fallo para cliente {body.get('clientId')}: {e}")
        return JSONResponse(content={"error": str(e)}, status_code=500)


def reward_benefit_bind_sp(json_file: dict):
    """Amarra el beneficio apartado a un prestamo recien creado."""
    try:
        data = _exec_sp("sp_rewardBenefits_bind", json_file)
        if "error" in data:
            return JSONResponse(content=data, status_code=500)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def reward_benefits_for_client_sp(json_file: dict):
    """Beneficios apartados o ya aplicados del cliente."""
    try:
        data = _exec_sp("sp_rewardBenefits_forClient", json_file)
        if "error" in data:
            return JSONResponse(content=data, status_code=500)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


# ---------------------------------------------------------------------------
# Aplicar el beneficio al calculo del prestamo
# ---------------------------------------------------------------------------

def apply_benefit(fee_mxn: float, annual_rate_pct: float, benefit: dict) -> tuple:
    """
    (comision, tasa) ya con el beneficio aplicado.

    Funcion pura y con tope: un beneficio corrupto o mal sembrado no puede
    dejar la comision negativa ni regalar la tasa entera.
    """
    if not benefit:
        return round(fee_mxn, 2), round(annual_rate_pct, 4)

    btype = benefit.get("benefitType")
    value = float(benefit.get("value") or 0)

    if btype == "fee_discount_pct":
        fee_mxn = fee_mxn * (1 - min(max(value, 0), 100) / 100.0)
    elif btype == "rate_discount_bps":
        annual_rate_pct = annual_rate_pct - (value / 100.0)

    return round(max(fee_mxn, 0.0), 2), round(max(annual_rate_pct, 0.0), 4)
