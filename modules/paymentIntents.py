from fastapi.responses import JSONResponse
from databases import connection
import json


def _conn():
    return connection()


def payment_intents_sp(json_file: dict):
    """create | expire_due | cancel | list via sp_paymentIntents.
    See sql/sp_paymentIntents.sql for the non-custodial boundary note —
    this table only ever records the EXPECTATION of a direct SPEI transfer,
    never moves money itself."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_paymentIntents] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        row = cursor.fetchone()
        json_result = row[0] if row and row[0] else '{"error":"no result"}'
        result = json.loads(json_result)
        _platform_fee_hooks(json_file, result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def _platform_fee_hooks(json_file: dict, result) -> None:
    """RFC-016 fase 3b — the lender's platform fee follows the FUNDING intent:
      create FUNDING (contract generated)  -> charge the lender's saved card
      expire_due / cancel (no disbursement) -> refund the fee in full
    Background and best-effort: a fee problem never changes this response."""
    try:
        from modules import platformFees
        req = (json_file.get("paymentIntents") or [{}])[0]
        action = req.get("action")
        if action == "create" and isinstance(result, dict) and result.get("paymentIntentId") \
                and result.get("intentType") == "FUNDING":
            platformFees.charge_fee_in_background(result.get("companyId"), result.get("loanId"),
                                                  result.get("payerClientId"))
        elif action == "expire_due" and isinstance(result, list) and result:
            import threading
            threading.Thread(target=platformFees.refund_fees_for_expired, args=(result,), daemon=True).start()
        elif action == "cancel" and isinstance(result, dict) and result.get("status") == "CANCELLED" \
                and req.get("loanId"):
            import threading
            threading.Thread(target=platformFees.refund_fee,
                             args=(req.get("companyId"), req.get("loanId"), "Fondeo cancelado"),
                             daemon=True).start()
    except Exception as e:
        print(f"[paymentIntents] platform fee hook not started: {e}")

