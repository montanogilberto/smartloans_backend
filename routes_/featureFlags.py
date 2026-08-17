from fastapi import APIRouter
from modules.featureFlags import is_non_custodial_funding_enabled

router = APIRouter()


@router.post(
    "/featureFlags",
    summary="Feature flags — dynamic, env-var-driven rollout gates",
    description="""
Body: { "featureFlags": [{ "companyId"?: int, "clientId"?: int }] }
Returns: { "nonCustodialFunding": bool }

RFC-002 Phase 1 rollout gate (docs/payments-action-plan.md). Controls whether
acceptProposal() uses paymentIntents/fundingTransactions declare/confirm
instead of the legacy disbursePayment(). Default false; enabled via
ENABLE_NON_CUSTODIAL_FUNDING_FLOW=true (global) or by adding companyId/
clientId to NON_CUSTODIAL_FUNDING_TEST_COMPANY_IDS / _TEST_CLIENT_IDS
(comma-separated env vars, Azure App Service config) — no deploy needed,
just a config change + app restart.
""",
)
def feature_flags(json: dict):
    item = (json.get("featureFlags") or [{}])[0]
    enabled = is_non_custodial_funding_enabled(item.get("companyId"), item.get("clientId"))
    return {"nonCustodialFunding": enabled}
