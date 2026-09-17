from fastapi import APIRouter
from modules.posRewards import (
    pos_reward_product_rates_sp,
    pos_reward_catalog_items_sp,
    pos_reward_balances_sp, pos_reward_dashboard_summary_sp,
    pos_reward_transactions_sp, earn_from_ticket_sp, adjust_points_sp,
    pos_reward_redemptions_sp, redeem_sp,
)

router = APIRouter()


@router.post(
    "/posRewardProductRates",
    summary="POS reward product rates CRUD (points per unit sold, per product)",
    description="""action 0 — read: { "posRewardProductRates": [{ "companyId": int, "productId"?: int }] }
action 1 — upsert (insert if no row exists for productId, else update):
  { "posRewardProductRates": [{ "action": 1, "companyId": int, "productId": int,
    "pointsPerUnit": number, "isActive"?: bool }] }
Read-only from a points-calculation standpoint -- the actual math never happens
client-side, see /posRewardTransactions/earn-from-ticket.""",
)
def pos_reward_product_rates(json: dict):
    return pos_reward_product_rates_sp(json)


@router.post(
    "/posRewardCatalogItems",
    summary="POS reward catalog CRUD (admin-managed redeemable rewards)",
    description="""action 0 — read: { "posRewardCatalogItems": [{ "companyId": int, "activeOnly"?: bool }] }
action 1 — insert / 2 — update / 3 — delete:
  { "posRewardCatalogItems": [{ "action": int, "companyId": int, "catalogItemId"?: int,
    "name": str, "rewardType": "discount_fixed|discount_pct|free_product",
    "requiredPoints": number, "discountValue"?: number, "freeProductId"?: int,
    "isActive"?: bool, "description"?: str }] }""",
)
def pos_reward_catalog_items(json: dict):
    return pos_reward_catalog_items_sp(json)


@router.post(
    "/posRewardBalances",
    summary="POS reward balances (materialized, read-only)",
    description="""{ "posRewardBalances": [{ "companyId": int, "clientId"?: int }] }
Never written directly -- see /posRewardTransactions/earn-from-ticket,
/posRewardTransactions/adjust and /posRewardRedemptions/redeem.""",
)
def pos_reward_balances(json: dict):
    return pos_reward_balances_sp(json)


@router.post(
    "/posRewardBalances/dashboard-summary",
    summary="POS reward admin dashboard summary (read-only, cross-table)",
    description="""{ "posRewardBalances": [{ "companyId": int, "startDate"?: "YYYY-MM-DD", "endDate"?: "YYYY-MM-DD" }] }
Returns { pointsIssued, pointsRedeemed, redemptionsCount,
topCustomers: [{clientId, balance, lifetimeEarned}], activity: [{date, earned, redeemed}] }.""",
)
def pos_reward_dashboard_summary(json: dict):
    return pos_reward_dashboard_summary_sp(json)


@router.post(
    "/posRewardTransactions",
    summary="POS reward ledger (read-only -- INSERT-only table, writes go through the endpoints below)",
    description="""{ "posRewardTransactions": [{ "companyId": int, "clientId"?: int, "txType"?: "EARN|REDEEM|ADJUSTMENT|EXPIRE" }] }""",
)
def pos_reward_transactions(json: dict):
    return pos_reward_transactions_sp(json)


@router.post(
    "/posRewardTransactions/earn-from-ticket",
    summary="Earn POS reward points from a completed ticket (server-side calculated)",
    description="""{ "posRewardTransactions": [{ "incomeId": int, "companyId": int }] }
Reads the ticket's incomeDetails lines, joins active posRewardProductRates per
productId, sums pointsPerUnit*quantity, posts one EARN row, and updates
posRewardBalances -- all inside one transaction. Idempotent per incomeId: a
retried call for an already-posted ticket returns the same result, never a
duplicate EARN row. Returns { pointsEarned, newBalance, transactionId }
(transactionId is null when the ticket had no rated products -- not an error).""",
)
def earn_from_ticket(json: dict):
    return earn_from_ticket_sp(json)


@router.post(
    "/posRewardTransactions/adjust",
    summary="Manual admin POS reward points adjustment",
    description="""{ "posRewardTransactions": [{ "companyId": int, "clientId": int, "points": number,
    "description": str, "createdByUserId": int }] }
points may be positive or negative. Returns { newBalance }.""",
)
def adjust_points(json: dict):
    return adjust_points_sp(json)


@router.post(
    "/posRewardRedemptions",
    summary="POS reward redemptions (read-only -- writes go through /posRewardRedemptions/redeem)",
    description="""{ "posRewardRedemptions": [{ "companyId": int, "clientId"?: int }] }""",
)
def pos_reward_redemptions(json: dict):
    return pos_reward_redemptions_sp(json)


@router.post(
    "/posRewardRedemptions/redeem",
    summary="Redeem a POS reward catalog item for a client",
    description="""{ "posRewardRedemptions": [{ "companyId": int, "clientId": int, "catalogItemId": int,
    "redeemedByUserId": int, "incomeId"?: int }] }
Transactional: checks balance >= requiredPoints, else rolls back and returns
{ error: 'insufficient_points', balance } (HTTP 200 -- a valid business
outcome, not a failure). On success inserts the redemption + a matching
REDEEM ledger row and decrements the balance. Returns
{ status: 'applied', redemptionId, pointsSpent, newBalance }.""",
)
def redeem(json: dict):
    return redeem_sp(json)
