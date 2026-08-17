import os
from fastapi import APIRouter
from modules.featureFlags import is_non_custodial_funding_enabled

router = APIRouter()


@router.post(
    "/featureFlags",
    summary="Feature flags — dynamic, env-var-driven rollout gates",
    description="""
Body: { "featureFlags": [{ "companyId"?: int, "clientId"?: int, "debug"?: bool }] }
Returns: { "nonCustodialFunding": bool }

RFC-002 Phase 1 rollout gate (docs/payments-action-plan.md). Controls whether
acceptProposal() uses paymentIntents/fundingTransactions declare/confirm
instead of the legacy disbursePayment(). Default false; enabled via
ENABLE_NON_CUSTODIAL_FUNDING_FLOW=true (global) or by adding companyId/
clientId to NON_CUSTODIAL_FUNDING_PILOT_COMPANY_IDS / _PILOT_CLIENT_IDS
(comma-separated env vars, Azure App Service config) — no deploy needed,
just a config change + app restart.

debug=true (TEMPORARY, remove once the pilot rollout is confirmed working):
adds a "raw" field with repr() of the three env vars this SP reads, so a
misconfigured/mistyped Azure App Service setting is visible directly instead
of guessing from the portal UI.
""",
)
def feature_flags(json: dict):
    item = (json.get("featureFlags") or [{}])[0]
    enabled = is_non_custodial_funding_enabled(item.get("companyId"), item.get("clientId"))
    result = {"nonCustodialFunding": enabled}
    if item.get("debug"):
        result["raw"] = {
            "ENABLE_NON_CUSTODIAL_FUNDING_FLOW": repr(os.environ.get("ENABLE_NON_CUSTODIAL_FUNDING_FLOW")),
            "NON_CUSTODIAL_FUNDING_PILOT_COMPANY_IDS": repr(os.environ.get("NON_CUSTODIAL_FUNDING_PILOT_COMPANY_IDS")),
            "NON_CUSTODIAL_FUNDING_PILOT_CLIENT_IDS": repr(os.environ.get("NON_CUSTODIAL_FUNDING_PILOT_CLIENT_IDS")),
            "all_env_keys_containing_CUSTODIAL": sorted(k for k in os.environ if "CUSTODIAL" in k.upper()),
        }
    return result
