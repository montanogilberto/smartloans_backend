import os


def _id_set(env_var: str) -> set:
    raw = os.getenv(env_var, "")
    ids = set()
    for part in raw.split(","):
        part = part.strip()
        if part.isdigit():
            ids.add(int(part))
    return ids


def is_non_custodial_funding_enabled(company_id=None, client_id=None) -> bool:
    """RFC-002 Phase 1 rollout gate (docs/payments-action-plan.md, POSVending
    repo, 2026-08-17 decision). Default OFF — the legacy disbursePayment()/
    loanDisbursements path stays the only path for all real traffic until
    explicitly allowlisted here. Controlled entirely via Azure App
    Service config / .env, no code change or deploy needed to flip it.

    There is only one environment (this App Service serves everyone — no
    separate staging backend exists yet), so "PILOT" here names the
    companies/clients currently piloting the new flow in production, not a
    separate test environment. Renamed from the earlier NON_CUSTODIAL_
    FUNDING_TEST_* names, which read as if a test environment existed:

        ENABLE_NON_CUSTODIAL_FUNDING_FLOW=true            — global on/off
        NON_CUSTODIAL_FUNDING_PILOT_COMPANY_IDS=1008      — comma-separated
        NON_CUSTODIAL_FUNDING_PILOT_CLIENT_IDS=2165,2167  — comma-separated

    Mutually exclusive per loan by design (not per company/session): the
    caller (acceptProposal()) checks this once before creating the loan and
    picks exactly one path — never both for the same loanId.
    """
    if os.getenv("ENABLE_NON_CUSTODIAL_FUNDING_FLOW", "false").strip().lower() == "true":
        return True
    if company_id is not None and int(company_id) in _id_set("NON_CUSTODIAL_FUNDING_PILOT_COMPANY_IDS"):
        return True
    if client_id is not None and int(client_id) in _id_set("NON_CUSTODIAL_FUNDING_PILOT_CLIENT_IDS"):
        return True
    return False
