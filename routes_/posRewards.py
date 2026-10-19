from fastapi import APIRouter
from modules.posRewards import (
    pos_reward_product_rates_sp,
    pos_reward_catalog_items_sp,
    pos_reward_balances_sp, pos_reward_dashboard_summary_sp, pos_rewards_dashboard_sp,
    pos_reward_transactions_sp, earn_from_ticket_sp, adjust_points_sp,
    pos_reward_redemptions_sp, redeem_sp,
    pos_reward_product_counts_sp,
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
    description="""The single table for every discount: coupons (coupon_b2g1), points
rewards (discount_fixed / discount_pct) and stamp cards (free_product).
action 0 — read: { "posRewardCatalogItems": [{ "companyId": int, "activeOnly"?: bool,
  "includeCoupons"?: bool (default false: coupons are typed at checkout, not redeemed),
  "clientId"?: int (leaves out first-purchase coupons once that client has a sale) }] }
action 1 — insert / 2 — update / 3 — delete:
  { "posRewardCatalogItems": [{ "action": int, "companyId": int, "catalogItemId"?: int,
    "name": str, "rewardType": "discount_fixed|discount_pct|free_product|coupon_b2g1",
    "requiredPoints": number (points; coupons 0), "discountValue"?: number,
    "freeProductId"?: int (free_product: the free product; coupon: only product discounted, null = all),
    "requiredUnits"?: number (free_product: purchases per free unit),
    "code"?: str (coupon), "startAtUtc"?: ISO, "endAtUtc"?: ISO, "firstPurchaseOnly"?: bool,
    "isActive"?: bool, "description"?: str }] }
On update, code/startAtUtc/endAtUtc/firstPurchaseOnly/requiredUnits change only when sent.""",
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
    "/posRewards/dashboard",
    summary="Rewards dashboard: points, liability, coupons, rewards, stamp cards, SmartLoans points (read-only)",
    description="""{ "posRewardsDashboard": [{ "companyId": int, "startDate"?: "YYYY-MM-DD", "endDate"?: "YYYY-MM-DD" }] }
(Hermosillo days; default the last 30 days)
→ { "result": [{ "period": {startDate, endDate},
  "kpis": { pointsEarned, pointsRedeemed, pointsAdjusted, outstandingPoints, outstandingValueMxn, earnPct,
            clientsWithBalance, activeClients, redemptions, couponUses, discountGiven, sales },
  "daily": [{date, earned, redeemed}],
  "topCustomers": [{clientId, name, balance, lifetimeEarned, lifetimeRedeemed, lastActivity}],
  "coupons": [{catalogItemId, code, name, isActive, firstPurchaseOnly, uses, discountTotal}],
  "rewards": [{catalogItemId, name, rewardType, requiredPoints, isActive, redemptions, cancelled, pointsSpent}],
  "stampCards": [{catalogItemId, name, freeProductId, requiredUnits, ready, oneAway, inProgress,
                  closest: [{clientId, name, unitsAvailable, requiredUnits}]}],
  "smartLoans": {purchaseRuleActive, pointsEarned, transactions, clients} | null }] }""",
)
def pos_rewards_dashboard(json: dict):
    return pos_rewards_dashboard_sp(json)


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


@router.post(
    "/posRewardProductCounts",
    summary="Per-product purchase counts for a client (stamp card progress)",
    description="""{ "posRewardProductCounts": [{ "companyId": int, "clientId": int }] }
Returns how many units of each rewardable product the client has purchased,
minus units already consumed by applied redemptions. Used by stamp-card UI
to show accurate progress per catalog item.""",
)
def pos_reward_product_counts(json: dict):
    return pos_reward_product_counts_sp(json)
