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


# ── Available credit (the peso limit shown as "Crédito disponible") ───────────
#
# DELIBERATELY DETERMINISTIC — no LLM. A credit limit is a regulated, auditable
# number: it must be reproducible and explainable, not model output. The score
# above already folds in the KYC/document signals (isVerified / pagaré /
# contract bonuses) and the full loan history; this only converts that score
# into a peso limit and applies the first-time promotion.
#
# All amounts in MXN. These are POLICY, not code — tune freely:
PROMO_FIRST_TIME_MXN   = 3000     # starter limit for a verified client with no
                                  # loan history yet ("promoción primera vez")
COMPANY_MAX_CREDIT_MXN = 50000    # hard ceiling regardless of score
CREDIT_ROUNDING_MXN    = 100      # round limits to friendly increments

# Proof of income — a credit limit must be capped by ABILITY TO REPAY, not just
# willingness (score). The limit can never exceed a multiple of verified monthly
# income, and without verified income the client is held to a low ceiling
# because repayment capacity is unproven.
INCOME_CREDIT_MULTIPLIER = 3      # limit ≤ 3× verified monthly income (DTI proxy)
NO_INCOME_MAX_MXN        = PROMO_FIRST_TIME_MXN  # cap when income is unverified

# Buró de Crédito — Mexico's real credit bureau. When a bureau pull is present
# it reflects the applicant's NATIONAL credit history (every lender), which is
# far more meaningful than our in-platform score, so it takes over as the
# scoring input and a serious bureau delinquency is a hard decline.
BURO_MIN_SCORE = 550              # below this on the bureau → decline

# Score (300–850) → base limit. First threshold met wins.
SCORE_LIMIT_TIERS = [
    (740, 20000, "TIER_A"),   # Excelente
    (670, 10000, "TIER_B"),   # Bueno
    (580,  5000, "TIER_C"),   # Regular
    (0,       0, "TIER_D"),   # Bajo → no credit offered
]


def _limit_from_score(score: int) -> tuple[int, str]:
    for threshold, limit, tier in SCORE_LIMIT_TIERS:
        if score >= threshold:
            return limit, tier
    return 0, "TIER_D"


def _compute_available_credit(score: int, data: dict) -> tuple[int, dict]:
    """Pure function: (score, aggregated data) -> (availableCredit_MXN, breakdown).

    Unit-testable, no DB, no LLM. `data` is the same aggregated dict
    _compute_score consumes, so this needs no extra inputs. Policy lives in the
    module constants above.
    """
    is_verified       = bool(data.get("isVerified"))
    contract_accepted = bool(data.get("contractAccepted"))
    outstanding       = float(data.get("outstandingBalance", 0) or 0)

    # Proof of income (from an uploaded/verified comprobante — see the SP that
    # feeds this dict). income_verified gates the larger limits.
    monthly_income    = float(data.get("monthlyIncome", 0) or 0)
    income_verified   = bool(data.get("incomeVerified"))

    # Buró de Crédito pull (optional — present only once the bureau integration
    # has run for this client with their consent). buro_score is on the same
    # 300–850 scale; buro_delinquent flags a serious past-due/default on file.
    buro_score        = data.get("buroScore")
    buro_delinquent   = bool(data.get("buroDelinquent"))
    has_buro          = buro_score is not None
    buro_score        = int(buro_score) if has_buro else None

    # A borrower "has history" if they've ever had a loan or made a payment.
    has_history = (
        int(data.get("totalPayments", 0)) > 0
        or int(data.get("paidLoans", 0)) > 0
        or int(data.get("activeLoans", 0)) > 0
    )

    now = datetime.now(timezone.utc).isoformat()

    def result(available: int, tier: str, reason: str, *, eligible: bool = True) -> tuple[int, dict]:
        return available, {
            "availableCredit": available,
            "tier": tier,
            "kycEligible": eligible,
            "isFirstTime": not has_history,
            "incomeVerified": income_verified,
            "monthlyIncome": monthly_income,
            "buroScore": buro_score,
            "buroDelinquent": buro_delinquent,
            "internalScore": score,
            "outstandingBalance": outstanding,
            "companyMax": COMPANY_MAX_CREDIT_MXN,
            "reason": reason,
            "score": buro_score if has_buro else score,
            "computedAt": now,
        }

    # 1. KYC gate — no verified identity + accepted contract, no credit at all.
    if not (is_verified and contract_accepted):
        return result(0, "INELIGIBLE",
                      "KYC incompleto: se requiere verificación biométrica y contrato aceptado.",
                      eligible=False)

    # 2. Buró de Crédito hard gate — a serious bureau delinquency, or a bureau
    #    score below the floor, is an automatic decline no matter how good the
    #    in-platform behaviour looks.
    if has_buro and (buro_delinquent or buro_score < BURO_MIN_SCORE):
        why = "morosidad reportada en Buró de Crédito" if buro_delinquent \
              else f"score de Buró {buro_score} por debajo del mínimo {BURO_MIN_SCORE}"
        return result(0, "BURO_DECLINED", f"Rechazado por {why}.")

    # 3. Choose the scoring input: the real bureau score dominates the tiny
    #    in-platform score when a pull exists.
    effective_score = buro_score if has_buro else score
    score_source = "Buró de Crédito" if has_buro else "score interno"

    # 4. First-time promotion vs. score-based tier.
    if not has_history and not has_buro:
        base, tier = PROMO_FIRST_TIME_MXN, "PROMO_FIRST_TIME"
        reason = "Promoción primera vez: verificación completa, sin historial aún."
    else:
        base, tier = _limit_from_score(effective_score)
        reason = f"Límite por {score_source} {effective_score} ({tier})."

    # 5. Ability-to-repay cap — never lend more than a multiple of verified
    #    income; without a verified income, hold to the low ceiling.
    if income_verified and monthly_income > 0:
        income_cap = int(monthly_income * INCOME_CREDIT_MULTIPLIER)
        if income_cap < base:
            base = income_cap
            tier = f"{tier}_INCOME_CAPPED"
            reason += f" Limitado por ingreso verificado (×{INCOME_CREDIT_MULTIPLIER})."
    else:
        if base > NO_INCOME_MAX_MXN:
            base = NO_INCOME_MAX_MXN
            tier = f"{tier}_NO_INCOME"
            reason += " Sin comprobante de ingresos verificado — límite reducido."

    # 6. Subtract what's already outstanding, clamp to the ceiling, round.
    available = base - outstanding
    available = max(0, min(COMPANY_MAX_CREDIT_MXN, available))
    available = int(available // CREDIT_ROUNDING_MXN * CREDIT_ROUNDING_MXN)

    return result(available, tier, reason)


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


async def compute_available_credit(payload: dict):
    """
    POST /credit-score/available-credit
    Computes the client's available credit limit (MXN) — the "Crédito
    disponible" shown on the dashboard — from their credit score + KYC signals
    + loan history. Deterministic; policy lives in the module constants.

    Returns { availableCredit, breakdown }. NOTE: persisting the amount onto
    clientDashboards.availableCredit is a DB write and must go through the
    posgmo-factory pipeline (sp_clientDashboards) — this handler computes and
    returns it so the dashboard can display it immediately, and so the value is
    always freshly derived rather than trusting a possibly-stale stored number.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    if not client_id or not company_id:
        return JSONResponse({"error": "clientId and companyId required"}, status_code=400)

    data = _fetch_score_data(int(client_id), int(company_id))
    score, _ = _compute_score(data)
    available, breakdown = _compute_available_credit(score, data)
    print(
        f"[creditScore] available-credit clientId={client_id} companyId={company_id} "
        f"score={score} tier={breakdown['tier']} kycEligible={breakdown['kycEligible']} "
        f"firstTime={breakdown['isFirstTime']} available={available}"
    )
    return JSONResponse({"availableCredit": available, "breakdown": breakdown}, status_code=200)


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
