import json
from fastapi.responses import JSONResponse
from databases import connection


def _sp(payload: dict) -> dict:
    conn = cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_incomePayments @pjsonfile = %s", (json.dumps({"incomePayments": [payload]}),))
        row = cursor.fetchone()
        raw = row[0] if row and row[0] else "{}"
        return json.loads(raw) if isinstance(raw, str) else raw
    finally:
        try:
            if cursor: cursor.close()
        except Exception: pass
        try:
            if conn: conn.close()
        except Exception: pass


def record_income_payments(income_id: int, payments: list[dict]) -> None:
    """Best-effort: records the payment-method breakdown for a split-payment
    sale (e.g. 60% Efectivo + 40% Tarjeta). Never raises -- the income row
    itself (total + a summary paymentMethod label) is already the source of
    truth for the sale; this only adds itemized detail for receipts/
    reporting. Called from modules/income.py right after a successful new
    income insert, same best-effort pattern as earn_points_for_income /
    post_income_journal_entry.

    KNOWN GAP (2026-10-01): the card-terminal commission hook in
    modules/income.py only fires for paymentMethod in ('tarjeta','terminal'),
    so a split sale's Tarjeta portion does not get a commission journal
    entry yet -- deliberate v1 scope, see the migration file's docstring."""
    if not payments:
        return
    try:
        result = _sp({"action": 1, "incomeId": income_id, "payments": payments})
        first = (result.get("result") or [{}])[0]
        if str(first.get("error") or "") == "1":
            print(f"[incomePayments] record failed for income {income_id}: {first.get('msg')}")
    except Exception as e:
        print(f"[incomePayments] record failed for income {income_id}: {e}")


def income_payments_sp(json_file: dict):
    """POST /incomePayments -- action 2 (list) only; writes go through
    record_income_payments, called internally from modules/income.py."""
    try:
        payload = (json_file.get("incomePayments") or [{}])[0]
        result = _sp(payload)
        first = (result.get("result") or [{}])[0]
        if str(first.get("error") or "") == "1":
            return JSONResponse(content=first, status_code=400)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
