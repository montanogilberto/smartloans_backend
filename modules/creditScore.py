"""
Credit Score Engine — POS GMO P2P Lending

Scoring model (300–850 range, modeled after Buró de Crédito Mexico):

  Component                        Weight   Max pts
  ─────────────────────────────────────────────────
  Payment history (on-time rate)    35%      297
  Outstanding balances / utilization 30%     255
  Length of credit history           15%     127
  New credit / recent proposals      10%      85
  Credit mix (loans + follow-ups)    10%      85
  ─────────────────────────────────────────────────
  BASE                                        849
  Biometric verification bonus               +25  (capped at 850 if >850)
  Pagaré signed bonus                        +15
  Contract accepted bonus                    +10

Inputs (all sourced from existing tables via SP):
  - stripeTransactions (on-time repayments vs late)
  - loans             (active, paid, delinquent counts)
  - loanProposals     (accepted/rejected ratio)
  - clientFollowUps   (at_risk / default riskStatus)
  - clientFaceRecognitions (isVerified, pagareAccepted, contractAccepted)
  - client.created_At (history length)
"""

from fastapi.responses import JSONResponse
from databases import connection
from datetime import datetime, timezone
import json
import math


def _conn():
    return connection()


# ── SP wrapper ───────────────────────────────────────────────────────────────

def _fetch_score_data(client_id: int, company_id: int) -> dict:
    """
    Calls sp_creditScore_data which returns a single JSON row with all
    aggregated inputs needed for the score calculation.
    """
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_creditScore_data] @pjsonfile = %s",
            (json.dumps({"creditScore": [{"clientId": client_id, "companyId": company_id}]}),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        print(f"[creditScore] DB error fetching data: {e}")
        return {}
    finally:
        if conn:
            conn.close()


def _save_score(client_id: int, company_id: int, score: int, breakdown: dict) -> None:
    """Persist computed score via sp_creditScores (upsert)."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_creditScores] @pjsonfile = %s",
            (json.dumps({
                "creditScores": [{
                    "action": "upsert",
                    "clientId": client_id,
                    "companyId": company_id,
                    "score": score,
                    "breakdown": json.dumps(breakdown),
                    "computedAt": datetime.now(timezone.utc).isoformat(),
                }]
            }),)
        )
    except Exception as e:
        print(f"[creditScore] DB error saving score: {e}")
    finally:
        if conn:
            conn.close()


# ── Core algorithm ───────────────────────────────────────────────────────────

def _compute_score(data: dict) -> tuple[int, dict]:
    """
    Pure function — takes aggregated data dict, returns (score, breakdown).
    Can be unit-tested independently of DB.
    """

    # ── 1. Payment history (35% → max 297 pts) ───────────────────────────
    total_payments  = int(data.get("totalPayments", 0))
    on_time         = int(data.get("onTimePayments", 0))
    late_payments   = int(data.get("latePayments", 0))
    defaults        = int(data.get("defaults", 0))

    if total_payments == 0:
        payment_score = 150  # neutral for new borrowers
    else:
        on_time_rate  = on_time / total_payments
        payment_score = int(297 * on_time_rate)
        payment_score -= defaults * 40       # -40 per default
        payment_score -= late_payments * 10  # -10 per late payment
        payment_score = max(0, payment_score)

    # ── 2. Utilization / outstanding balance (30% → max 255 pts) ─────────
    total_credit    = float(data.get("totalCreditLimit", 0))
    used_credit     = float(data.get("outstandingBalance", 0))

    if total_credit <= 0:
        utilization_score = 127  # neutral
    else:
        utilization = used_credit / total_credit
        if utilization <= 0.10:   utilization_score = 255
        elif utilization <= 0.30: utilization_score = 230
        elif utilization <= 0.50: utilization_score = 180
        elif utilization <= 0.70: utilization_score = 120
        elif utilization <= 0.90: utilization_score = 60
        else:                     utilization_score = 0

    # ── 3. Length of credit history (15% → max 127 pts) ──────────────────
    first_loan_months = int(data.get("creditAgeMonths", 0))
    if first_loan_months >= 60:   history_score = 127
    elif first_loan_months >= 24: history_score = int(127 * first_loan_months / 60)
    elif first_loan_months >= 6:  history_score = int(80 * first_loan_months / 24)
    else:                         history_score = max(10, first_loan_months * 8)

    # ── 4. New credit / recent proposals (10% → max 85 pts) ──────────────
    proposals_last_90 = int(data.get("proposalsLast90Days", 0))
    if proposals_last_90 == 0:    new_credit_score = 85
    elif proposals_last_90 == 1:  new_credit_score = 70
    elif proposals_last_90 == 2:  new_credit_score = 50
    elif proposals_last_90 == 3:  new_credit_score = 30
    else:                         new_credit_score = 10

    # ── 5. Credit mix (10% → max 85 pts) ─────────────────────────────────
    paid_loans       = int(data.get("paidLoans", 0))
    active_loans     = int(data.get("activeLoans", 0))
    followup_at_risk = int(data.get("followUpAtRisk", 0))
    followup_default = int(data.get("followUpDefault", 0))

    mix_score = 40  # baseline
    mix_score += min(paid_loans * 10, 30)       # reward paid loans
    mix_score += min(active_loans * 5, 15)      # small reward for active
    mix_score -= followup_at_risk * 8           # penalty per at-risk follow-up
    mix_score -= followup_default * 20          # heavy penalty per default flag
    mix_score = max(0, min(85, mix_score))

    # ── Sum & bonus ───────────────────────────────────────────────────────
    base = payment_score + utilization_score + history_score + new_credit_score + mix_score

    biometric_bonus  = 25 if data.get("isVerified")        else 0
    pagare_bonus     = 15 if data.get("pagareAccepted")    else 0
    contract_bonus   = 10 if data.get("contractAccepted")  else 0

    raw_score = base + biometric_bonus + pagare_bonus + contract_bonus

    # Clamp to 300–850 range
    score = max(300, min(850, raw_score + 300))

    breakdown = {
        "score": score,
        "components": {
            "paymentHistory":    {"points": payment_score,      "weight": "35%", "max": 297},
            "utilization":       {"points": utilization_score,  "weight": "30%", "max": 255},
            "creditAge":         {"points": history_score,      "weight": "15%", "max": 127},
            "newCredit":         {"points": new_credit_score,   "weight": "10%", "max": 85},
            "creditMix":         {"points": mix_score,           "weight": "10%", "max": 85},
        },
        "bonuses": {
            "biometricVerified": biometric_bonus,
            "pagareAccepted":    pagare_bonus,
            "contractAccepted":  contract_bonus,
        },
        "inputs": {
            "totalPayments":     total_payments,
            "onTimePayments":    on_time,
            "latePayments":      late_payments,
            "defaults":          defaults,
            "utilization":       round(used_credit / total_credit * 100, 1) if total_credit > 0 else 0,
            "creditAgeMonths":   first_loan_months,
            "proposalsLast90":   proposals_last_90,
            "paidLoans":         paid_loans,
            "activeLoans":       active_loans,
        },
        "label": _score_label(score),
        "computedAt": datetime.now(timezone.utc).isoformat(),
    }

    return score, breakdown


def _score_label(score: int) -> str:
    if score >= 750: return "Excelente"
    if score >= 700: return "Muy bueno"
    if score >= 650: return "Bueno"
    if score >= 600: return "Regular"
    if score >= 550: return "Bajo"
    return "Muy bajo"


# ── Public handlers ──────────────────────────────────────────────────────────

async def compute_credit_score(payload: dict):
    """
    POST /credit-score/compute
    Recomputes and persists the credit score for a client.
    Returns full breakdown.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    if not client_id or not company_id:
        return JSONResponse({"error": "clientId and companyId required"}, status_code=400)

    data = _fetch_score_data(int(client_id), int(company_id))
    score, breakdown = _compute_score(data)
    _save_score(int(client_id), int(company_id), score, breakdown)
    return JSONResponse({"creditScore": breakdown}, status_code=200)


async def get_credit_score(payload: dict):
    """
    POST /credit-score
    Returns the last persisted score. Triggers a recompute if older than 24h.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    if not client_id or not company_id:
        return JSONResponse({"error": "clientId and companyId required"}, status_code=400)

    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_creditScores] @pjsonfile = %s",
            (json.dumps({
                "creditScores": [{
                    "action": "get",
                    "clientId": int(client_id),
                    "companyId": int(company_id),
                }]
            }),)
        )
        row = cursor.fetchone()
        stored = json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        stored = {}
        print(f"[creditScore] get error: {e}")
    finally:
        if conn:
            conn.close()

    # Recompute if stale (>24h) or not found
    computed_at = stored.get("computedAt")
    stale = True
    if computed_at:
        try:
            age_hours = (datetime.now(timezone.utc) - datetime.fromisoformat(computed_at)).total_seconds() / 3600
            stale = age_hours > 24
        except Exception:
            stale = True

    if stale:
        return await compute_credit_score(payload)

    return JSONResponse({"creditScore": stored}, status_code=200)


async def get_credit_score_history(payload: dict):
    """
    POST /credit-score/history
    Returns the score trend over time for a client (for charts).
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_creditScores] @pjsonfile = %s",
            (json.dumps({
                "creditScores": [{
                    "action": "history",
                    "clientId": int(client_id),
                    "companyId": int(company_id),
                }]
            }),)
        )
        rows = cursor.fetchall()
        json_result = "".join(r[0] for r in rows if r and r[0])
        return JSONResponse(json.loads(json_result) if json_result else {"history": []}, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
