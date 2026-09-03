from fastapi import APIRouter
from modules.chartOfAccounts import chart_of_accounts_sp, all_chart_of_accounts_sp, one_chart_of_account_sp

router = APIRouter()


@router.post(
    "/chartOfAccounts",
    summary="Chart of Accounts CRUD (Catálogo de Cuentas)",
    description="""
action 1 — create:
  { "chartOfAccounts": [{ "action": 1, "companyId": int, "code": str, "name": str,
    "accountType": "ASSET|LIABILITY|EQUITY|INCOME|EXPENSE", "parentAccountId"?: int,
    "level"?: int, "isPostable"?: bool }] }
  normalBalance is always derived server-side from accountType — never trust the client.
action 2 — update (name/jerarquía/estado; code/accountType/normalBalance son inmutables):
  { "chartOfAccounts": [{ "action": 2, "accountId": int, "companyId": int, "name"?: str,
    "isActive"?: bool, "isPostable"?: bool, "parentAccountId"?: int }] }
action 3 — deactivate (nunca DELETE):
  { "chartOfAccounts": [{ "action": 3, "accountId": int, "companyId": int }] }
""",
)
def chart_of_accounts(json: dict):
    return chart_of_accounts_sp(json)


@router.post(
    "/all_chartOfAccounts",
    summary="List a company's chart of accounts",
    description="""Body: { "chartOfAccounts": [{ "companyId": int, "accountType"?: str }] }
Returns ALL accounts (active and inactive) ordered by code — the frontend badges inactive ones.""",
)
def all_chart_of_accounts(json: dict):
    return all_chart_of_accounts_sp(json)


@router.post(
    "/chartOfAccounts/one",
    summary="Get a single account by id",
    description="""Body: { "chartOfAccounts": [{ "accountId": int }] }""",
)
def one_chart_of_account(json: dict):
    return one_chart_of_account_sp(json)
