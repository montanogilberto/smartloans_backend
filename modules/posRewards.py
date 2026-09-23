"""
POS loyalty rewards — points earned from POS/vending ticket sales, spent
against an admin-managed catalog. Logically and structurally separate from
modules/rewards.py (loan-behavior rewardTransactions/rewardBalances) and from
any arcade chip ledger: no FK, no shared endpoint, no conversion function.

Spec: posgmo-factory/tests/prd_posRewardProductRate.json,
      prd_posRewardCatalogItem.json, prd_posRewardBalance.json,
      prd_posRewardTransaction.json, prd_posRewardRedemption.json
SQL: sql/sp_posRewards.sql

Points are always calculated server-side (sp_posRewardTransactions_earnFromTicket
reads incomeDetails + posRewardProductRates) -- this module never sums points
from a frontend-supplied value.
"""

import json
from fastapi.responses import JSONResponse
from databases import connection


def _conn():
    return connection()


def _sp(proc: str, json_file: dict):
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(f"EXEC [dbo].[{proc}] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        raw = "".join(r[0] for r in rows if r and r[0])
        return json.loads(raw) if raw else {}
    finally:
        if conn:
            conn.close()


def _crud_status(result: dict) -> int:
    """The 'result[0].error' convention used by sp_posReward* CRUD SPs
    (mirrors modules/products.py / modules/income.py): '1' = failed."""
    try:
        row = result.get("result", [{}])[0]
        return 400 if str(row.get("error") or "") == "1" else 200
    except Exception:
        return 200


# ── Product rates (companion to products) ───────────────────────────────────

def pos_reward_product_rates_sp(json_file: dict):
    """CRUD passthrough (sp_posRewardProductRates). action 0=read, 1=upsert."""
    try:
        result = _sp("sp_posRewardProductRates", json_file)
        return JSONResponse(result, status_code=_crud_status(result))
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


# ── Catalog (admin-managed redeemable rewards) ──────────────────────────────

def pos_reward_catalog_items_sp(json_file: dict):
    """CRUD passthrough (sp_posRewardCatalogItems). action 0=read, 1/2/3=insert/update/delete."""
    try:
        result = _sp("sp_posRewardCatalogItems", json_file)
        return JSONResponse(result, status_code=_crud_status(result))
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


# ── Balances (materialized projection) ──────────────────────────────────────

def pos_reward_balances_sp(json_file: dict):
    """Read-only passthrough (sp_posRewardBalances). Never written directly --
    see earn/adjust/redeem below."""
    try:
        result = _sp("sp_posRewardBalances", json_file)
        return JSONResponse(result, status_code=_crud_status(result))
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def pos_reward_dashboard_summary_sp(json_file: dict):
    """POST /posRewardBalances/dashboard-summary -- read-only cross-table
    aggregation. topCustomersJson/activityJson come back as JSON-encoded
    *string* columns (built from T-SQL variables, not an inline FOR JSON
    subquery) -- decode them here, same reasoning as
    modules/journalEntries.py::journal_entries_trial_balance_sp."""
    try:
        result = _sp("sp_posRewardBalances_dashboardSummary", json_file)
        if isinstance(result, dict):
            if isinstance(result.get("topCustomersJson"), str):
                result["topCustomers"] = json.loads(result.pop("topCustomersJson"))
            if isinstance(result.get("activityJson"), str):
                result["activity"] = json.loads(result.pop("activityJson"))
        return JSONResponse(result, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


# ── Ledger (append-only) ─────────────────────────────────────────────────────

def pos_reward_transactions_sp(json_file: dict):
    """CRUD passthrough (sp_posRewardTransactions). action 0=read only --
    1/2/3 are rejected by the SP itself (INSERT-only ledger, writes go
    through earn-from-ticket/adjust below)."""
    try:
        result = _sp("sp_posRewardTransactions", json_file)
        return JSONResponse(result, status_code=_crud_status(result))
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def earn_from_ticket_sp(json_file: dict):
    """POST /posRewardTransactions/earn-from-ticket -- the ONLY path allowed
    to insert EARN rows. Idempotent per (companyId, incomeId): a retried call
    for an already-posted ticket returns the prior result instead of erroring."""
    try:
        result = _sp("sp_posRewardTransactions_earnFromTicket", json_file)
        status_code = 400 if isinstance(result, dict) and result.get("error") else 200
        return JSONResponse(result, status_code=status_code)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def adjust_points_sp(json_file: dict):
    """POST /posRewardTransactions/adjust -- manual admin points adjustment."""
    try:
        result = _sp("sp_posRewardTransactions_adjust", json_file)
        status_code = 400 if isinstance(result, dict) and result.get("error") else 200
        return JSONResponse(result, status_code=status_code)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


# ── Redemptions ───────────────────────────────────────────────────────────

def pos_reward_redemptions_sp(json_file: dict):
    """Read-only passthrough (sp_posRewardRedemptions). Writes go through
    /posRewardRedemptions/redeem below."""
    try:
        result = _sp("sp_posRewardRedemptions", json_file)
        return JSONResponse(result, status_code=_crud_status(result))
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def redeem_sp(json_file: dict):
    """POST /posRewardRedemptions/redeem. 'insufficient_points' is a valid
    business outcome, not a failure -- it must come back as HTTP 200 so the
    frontend's typed union (RedeemResult | InsufficientPointsError) resolves
    instead of throwing. Any other {"error": ...} is a real failure (bad
    catalogItemId, missing params) -> 400."""
    try:
        result = _sp("sp_posRewardRedemptions_redeem", json_file)
        if isinstance(result, dict) and result.get("error") == "insufficient_points":
            return JSONResponse(result, status_code=200)
        status_code = 400 if isinstance(result, dict) and result.get("error") else 200
        return JSONResponse(result, status_code=status_code)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


def pos_reward_product_counts_sp(json_file: dict):
    """POST /posRewardProductCounts — returns units purchased per rewardable
    product for a client, minus units already consumed by applied redemptions.
    Runs directly against incomeDetails + posRewardRedemptions so the stamp
    card UI shows accurate per-product progress without a custom table."""
    try:
        result = _sp("sp_posRewardProductCounts", json_file)
        # SP returns {"posRewardProductCounts": [...]} — wrap in result envelope
        if isinstance(result, dict) and "posRewardProductCounts" in result:
            result = {"result": [result]}
        return JSONResponse(result, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
