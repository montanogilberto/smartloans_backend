import json
from fastapi.responses import JSONResponse
from databases import connection


def _sp(payload: dict):
    conn = cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_rewards] @pjsonfile = %s", (json.dumps({"rewards": [payload]}),))
        row = cursor.fetchone()
        raw = row[0] if row and row[0] else "{}"
        return json.loads(raw) if isinstance(raw, str) else raw
    except Exception as e:
        return {"error": str(e)}
    finally:
        try:
            if cursor: cursor.close()
        except Exception: pass
        try:
            if conn: conn.close()
        except Exception: pass


def rewards_sp(payload: dict):
    print("[rewards_sp] action:", payload.get("action"), "company:", payload.get("companyId"))
    result = _sp(payload)
    if "error" in result:
        return JSONResponse(content=result, status_code=400)
    return JSONResponse(content=result, status_code=200)


def _active_purchase_rule(company_id: int) -> dict | None:
    rules = _sp({"action": "list_rules", "companyId": company_id})
    if not isinstance(rules, list):
        return None
    for rule in rules:
        if rule.get("ruleType") == "purchase" and rule.get("isActive"):
            return rule
    return None


def earn_points_for_income(company_id: int, client_id: int, income_id: int, total) -> dict | None:
    """Best-effort: auto-earns loyalty points for a completed POS sale, the
    same way a sale auto-posts to the accounting ledger (see
    modules/journalEntries.py::post_income_journal_entry) and dispatches a
    client notification. Never raises -- a missing/inactive 'purchase'
    rewardRule just means no points for this sale, not an error.

    referenceId is always the real incomeId, so rewardTransactions rows can
    be traced back to the sale that produced them -- previously nothing in
    this codebase ever called sp_rewards' 'earn' action with a real
    incomeId (the frontend's posRewardsApi.earnFromTicket() calls backend
    routes that don't exist here, so POS sales were silently earning zero
    points). This is the fix: earning now happens server-side, on the
    SAME write path every income insert already goes through, so it
    applies uniformly whether the sale came from the cart checkout screen
    or the chat-based CREATE_INCOME agent flow.

    clientId=1 is the walk-in/"mostrador" placeholder CartPage.tsx sends
    when no real client was scanned/selected (dbo.income.clientId is
    NOT NULL, so the sale itself still needs SOME value there) -- excluded
    here so anonymous counter sales don't silently accrue points onto
    whichever real client happens to hold id 1.
    """
    try:
        if not client_id or not total or client_id == 1:
            return None
        rule = _active_purchase_rule(company_id)
        if not rule:
            return None
        min_amount = rule.get("minAmount")
        if min_amount and float(total) < float(min_amount):
            return None
        points_per_unit = float(rule.get("pointsPerUnit") or 0)
        if points_per_unit <= 0:
            return None
        points = round(float(total) * points_per_unit)
        max_points = rule.get("maxPointsPerTx")
        if max_points:
            points = min(points, int(max_points))
        if points <= 0:
            return None
        return _sp({
            "action": "earn",
            "companyId": company_id,
            "clientId": client_id,
            "ruleId": rule.get("ruleId"),
            "points": points,
            "referenceId": str(income_id),
            "description": f"Venta POS #{income_id}",
        })
    except Exception as e:
        print(f"[rewards] auto-earn for income {income_id} failed: {e}")
        return None
