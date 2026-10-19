"""
POS loyalty rewards — points earned from POS/vending ticket sales, spent
against an admin-managed catalog. Logically and structurally separate from
modules/rewards.py (loan-behavior rewardTransactions/rewardBalances) and from
any arcade chip ledger: no FK, no shared endpoint, no conversion function.

Spec: posgmo-factory/tests/prd_posRewardProductRate.json,
      prd_posRewardCatalogItem.json, prd_posRewardBalance.json,
      prd_posRewardTransaction.json, prd_posRewardRedemption.json
SQL: sql/sp_posRewards.sql, sql/sp_income_applyDiscounts.sql (coupons + rewards on a sale)

Points are always calculated server-side (sp_posRewardTransactions_earnFromTicket
reads incomeDetails + posRewardProductRates) -- this module never sums points
from a frontend-supplied value.
"""

import json
import re
from fastapi.responses import JSONResponse
from databases import connection

# dbo.posRewardCatalogItems is the single table for coupons, points rewards
# and stamp cards (docs/promotions_rewards_analysis.md). Run in this order.
POS_REWARDS_MIGRATION_FILES = (
    "sql/migrations/2026-10-16c_unify_promotions_into_reward_catalog.sql",
    "sql/migrations/2026-10-18_pos_rewards_integrity.sql",
    "sql/migrations/2026-10-18b_pos_rewards_earn_pct.sql",
    "sql/sp_posRewards.sql",
    "sql/sp_posRewardFreeProductStatus.sql",
    "sql/sp_whatsappCustomerRewards.sql",
    "sql/sp_promotions.sql",
    "sql/sp_income_applyDiscounts.sql",
)


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


# ---------------------------------------------------------------------------
# Server-side earn + the rewards line of the sale's WhatsApp/push message
# ---------------------------------------------------------------------------
WALK_IN_CLIENT_ID = 1  # CartPage's "mostrador" placeholder: never earns


def _fmt_points(value) -> str:
    try:
        n = float(value or 0)
    except (TypeError, ValueError):
        n = 0.0
    return str(int(n)) if n.is_integer() else f"{n:.2f}"


def earn_and_summarize(json_file: dict) -> dict | None:
    """Posts this sale's POS points and returns what the customer message
    needs: {pointsEarned, balance, catalog}. None for walk-in sales or on any
    error: the sale message then simply goes out without a rewards line.

    json_file is the same payload as POST /posRewardTransactions/earn-from-ticket,
    passed straight to the SP (idempotent per ticket — the cart's own
    earnFromTicket call afterwards just replays this result):
        {"posRewardTransactions": [{"companyId": 1, "clientId": 2260, "incomeId": 4868}]}"""
    row = ((json_file or {}).get("posRewardTransactions") or [{}])[0] or {}
    company_id, client_id = row.get("companyId"), row.get("clientId")
    if not company_id or not client_id or int(client_id) == WALK_IN_CLIENT_ID:
        return None
    try:
        earned = _sp("sp_posRewardTransactions_earnFromTicket", json_file)
        if not isinstance(earned, dict) or earned.get("error"):
            print(f"[posRewards] earn failed for {row}: {earned}")
            return None
        return {
            "pointsEarned": float(earned.get("pointsEarned") or 0),
            "balance": float(earned.get("newBalance") or 0),
            "catalog": _client_catalog(int(company_id), int(client_id)),
        }
    except Exception as e:
        print(f"[posRewards] earn/summary failed for {row}: {type(e).__name__}: {e}")
        return None


def _result_rows(res, key: str) -> list:
    if not isinstance(res, dict) or res.get("error"):
        return []
    return ((res.get("result") or [{}])[0] or {}).get(key) or []


def _client_catalog(company_id: int, client_id: int) -> list:
    """Active rewards (no coupons), stamp cards with this client's units."""
    items = _result_rows(_sp("sp_posRewardCatalogItems", {"posRewardCatalogItems": [
        {"action": 0, "companyId": company_id, "activeOnly": 1}]}), "posRewardCatalogItems")
    catalog = [i for i in items if i.get("isActive") in (True, 1, "1")]
    if any(_is_free_product(i) for i in catalog):
        catalog = _with_free_product_units(catalog, company_id, client_id)
    return catalog


def ticket_rewards(company_id, income_id, client_id=None) -> dict | None:
    """The rewards block of a printed / digital ticket — the same lines as the
    sale message: {pointsEarned, balance, lines}. Read-only, never earns:
    pointsEarned and balance come from this sale's EARN row (balance right
    after the sale, so a reprint shows the same numbers); the goal lines use
    the catalog and stamp-card progress as they are now. None for walk-in
    sales, when the client is unknown, or on any error (the ticket simply
    prints without the block)."""
    try:
        company_id, income_id = int(company_id), int(income_id)
        if client_id is None:
            incomes = (_sp("sp_income_one", {"income": [{"incomeId": income_id, "companyId": company_id}]})
                       or {}).get("income") or []
            client_id = incomes[0].get("clientId") if incomes else None
        if not client_id or int(client_id) == WALK_IN_CLIENT_ID:
            return None
        client_id = int(client_id)

        earns = _result_rows(_sp("sp_posRewardTransactions", {"posRewardTransactions": [
            {"action": 0, "companyId": company_id, "clientId": client_id, "txType": "EARN"}]}),
            "posRewardTransactions")
        earn = next((t for t in earns if t.get("referenceType") == "ticket"
                     and str(t.get("referenceId")) == str(income_id)), None)
        if earn:
            earned, balance = float(earn.get("points") or 0), float(earn.get("balanceAfter") or 0)
        else:
            balances = _result_rows(_sp("sp_posRewardBalances", {"posRewardBalances": [
                {"action": 0, "companyId": company_id, "clientId": client_id}]}), "posRewardBalances")
            earned, balance = 0.0, float((balances[0] if balances else {}).get("balance") or 0)

        label = rewards_label({"pointsEarned": earned, "balance": balance,
                               "catalog": _client_catalog(company_id, client_id)})
        if not label:
            return None
        return {"pointsEarned": earned, "balance": balance, "lines": label.split("\n")}
    except Exception as e:
        print(f"[posRewards] ticket rewards failed for income {income_id}: {type(e).__name__}: {e}")
        return None


def _is_free_product(item: dict) -> bool:
    return item.get("rewardType") == "free_product"


def _with_free_product_units(catalog: list, company_id: int, client_id: int) -> list:
    """free_product rewards are earned by buying that product, not with the
    points balance (sp_posRewardRedemptions_redeem checks units). Adds
    unitsRequired/unitsAvailable from sp_posRewardFreeProductStatus, which runs
    the redeem SP's own unit check. If it fails, free products are dropped
    from the line rather than promised on the points balance."""
    status = {}
    try:
        res = _sp("sp_posRewardFreeProductStatus", {"posRewardFreeProductStatus": [
            {"companyId": company_id, "clientId": client_id}]})
        rows = []
        if isinstance(res, dict) and not res.get("error"):
            rows = ((res.get("result") or [{}])[0] or {}).get("posRewardFreeProductStatus") or []
        status = {r.get("catalogItemId"): r for r in rows}
    except Exception as e:
        print(f"[posRewards] free product status failed for client {client_id}: {type(e).__name__}: {e}")
    out = []
    for item in catalog:
        if not _is_free_product(item):
            out.append(item)
        elif item.get("catalogItemId") in status:
            st = status[item["catalogItemId"]]
            out.append({**item, "unitsRequired": float(st.get("requiredUnits") or 0),
                        "unitsAvailable": float(st.get("unitsAvailable") or 0)})
    return out


def _stamp_product(item: dict) -> str | None:
    """'Servicio Completo gratis (3x1)' -> 'Servicio Completo' (the product a
    stamp card counts); None if the name doesn't follow that pattern."""
    m = re.match(r"^(.*?)\s+gratis\b", str(item.get("name") or ""), re.IGNORECASE)
    return m.group(1).strip() if m and m.group(1).strip() else None


def _falta(missing: float) -> str:
    return "Te falta" if missing == 1 else "Te faltan"


def rewards_label(summary: dict | None) -> str:
    """The rewards block of the sale message, one goal per line, e.g.
        Puntos: +4.50 · Saldo: 4.50 pts
        Te faltan 5.50 pts para $10 de descuento
        Te faltan 2 Servicio Completo para el siguiente gratis
    Line 1: points earned and balance. Then, at most:
      - rewards ready now (stamp cards first, then points rewards, most
        valuable first): '¡Ya puedes canjear: X y N más!'
      - the next points reward, if none is ready yet (judged on the balance)
      - the closest stamp card the client has started and not completed
        (judged on units bought of that product — unitsRequired/unitsAvailable,
        the redeem rule)
    '' when there is nothing to say (walk-in, rewards error, no points)."""
    if not summary:
        return ""
    earned, balance = summary.get("pointsEarned", 0), summary.get("balance", 0)
    catalog = summary.get("catalog") or []
    if earned <= 0 and balance <= 0:
        return ""

    head = []
    if earned > 0:
        head.append(f"Puntos: +{_fmt_points(earned)}")
    head.append(f"Saldo: {_fmt_points(balance)} pts")
    lines = [" · ".join(head)]

    by_points = sorted((i for i in catalog if not _is_free_product(i)),
                       key=lambda i: float(i.get("requiredPoints") or 0))
    free = [i for i in catalog if _is_free_product(i) and "unitsRequired" in i]

    points_ready = [i for i in reversed(by_points) if float(i.get("requiredPoints") or 0) <= balance]
    ready = [i for i in free if i["unitsAvailable"] >= i["unitsRequired"]] + points_ready
    if ready:
        more = len(ready) - 1
        lines.append(f"¡Ya puedes canjear: {ready[0].get('name')}" + (f" y {more} más" if more else "") + "!")

    if not points_ready and by_points:
        nxt = by_points[0]
        missing = float(nxt.get("requiredPoints") or 0) - balance
        lines.append(f"{_falta(missing)} {_fmt_points(missing)} {'pt' if missing == 1 else 'pts'} para {nxt.get('name')}")

    started = [i for i in free if 0 < i["unitsAvailable"] < i["unitsRequired"]]
    if started:
        nxt = min(started, key=lambda i: i["unitsRequired"] - i["unitsAvailable"])
        missing = nxt["unitsRequired"] - nxt["unitsAvailable"]
        product = _stamp_product(nxt)
        if product:
            lines.append(f"{_falta(missing)} {_fmt_points(missing)} {product} para el siguiente gratis")
        else:
            lines.append(f"{_falta(missing)} {_fmt_points(missing)} {'compra' if missing == 1 else 'compras'} para: {nxt.get('name')}")
    return "\n".join(lines)

    # Nothing ready: the free product the client has started buying that is
    # closest, else the cheapest points reward.
    started = [i for i in free if i["unitsAvailable"] > 0]
    if started:
        nxt = min(started, key=lambda i: i["unitsRequired"] - i["unitsAvailable"])
        missing = nxt["unitsRequired"] - nxt["unitsAvailable"]
        word = "compra" if missing == 1 else "compras"
        parts.append(f"Le {'falta' if missing == 1 else 'faltan'} {_fmt_points(missing)} {word} para: {nxt.get('name')}")
    elif by_points:
        nxt = by_points[0]
        missing = float(nxt.get("requiredPoints") or 0) - balance
        unit = "pt" if missing == 1 else "pts"
        parts.append(f"Le {'falta' if missing == 1 else 'faltan'} {_fmt_points(missing)} {unit} para: {nxt.get('name')}")
    return " · ".join(parts)
