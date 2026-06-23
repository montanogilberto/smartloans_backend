from fastapi import APIRouter
from modules.creditScore import compute_credit_score, get_credit_score, get_credit_score_history

router = APIRouter(prefix="/credit-score", tags=["Credit Score"])


@router.post(
    "",
    summary="Get credit score for a client (auto-recomputes if stale)",
    description="""
Returns the cached credit score if < 24h old, otherwise recomputes it.
Score range: 300–850 (modeled after Buró de Crédito Mexico).

Components: payment history (35%), utilization (30%), credit age (15%),
new credit (10%), credit mix (10%) + biometric/pagaré/contract bonuses.

Body: { "clientId": int, "companyId": int }
Returns: { "creditScore": { score, label, components, bonuses, inputs, computedAt } }
""",
)
async def credit_score(json: dict):
    return await get_credit_score(json)


@router.post(
    "/compute",
    summary="Force recompute credit score",
    description="""
Forces a fresh computation from the database regardless of age.
Use after a loan payment or proposal acceptance.

Body: { "clientId": int, "companyId": int }
""",
)
async def compute_score(json: dict):
    return await compute_credit_score(json)


@router.post(
    "/history",
    summary="Get credit score history for trend chart",
    description="""
Returns all historical score snapshots for a client, ordered by date.
Used to render a score trend line chart in the dashboard.

Body: { "clientId": int, "companyId": int }
Returns: { "history": [{ score, label, computedAt }] }
""",
)
async def score_history(json: dict):
    return await get_credit_score_history(json)
