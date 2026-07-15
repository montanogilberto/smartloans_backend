"""
Platform Wallet Balance — POS GMO P2P Lending

Tracks each lender's available capital on the platform:
  balance = SUM(top-ups) - SUM(disbursements) + SUM(repayments_received)

The wallet is a logical balance stored in SQL (mirroring Stripe transfers).
It is NOT a Stripe balance — it reflects the platform's bookkeeping view.

Table: clientWallets
  walletId, clientId, companyId,
  totalTopUps, totalDisbursed, totalRepaid,
  availableBalance  (computed: totalTopUps - totalDisbursed + totalRepaid),
  reservedBalance   (funds committed to accepted proposals pending disbursement),
  updatedAt
"""

from fastapi.responses import JSONResponse
from databases import connection
import json
from datetime import datetime, timezone


def _conn():
    return connection()


def _sp_wallet(payload: dict) -> dict:
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_clientWallets] @pjsonfile = %s",
            (json.dumps({"wallets": [payload]}),)
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else {}
    except Exception as e:
        print(f"[walletBalance] DB error: {e}")
        return {}
    finally:
        if conn:
            conn.close()


async def get_wallet(payload: dict):
    """GET wallet balance for a client."""
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    if not client_id or not company_id:
        return JSONResponse({"error": "clientId and companyId required"}, status_code=400)

    result = _sp_wallet({
        "action": "get",
        "clientId": int(client_id),
        "companyId": int(company_id),
    })

    if not result:
        # Return zero-balance wallet if not yet created
        return JSONResponse({
            "wallet": {
                "clientId": int(client_id),
                "companyId": int(company_id),
                "availableBalance": 0,
                "reservedBalance": 0,
                "totalTopUps": 0,
                "totalDisbursed": 0,
                "totalRepaid": 0,
            }
        }, status_code=200)

    return JSONResponse({"wallet": result}, status_code=200)


async def credit_wallet(payload: dict):
    """
    Credit the wallet after a successful top-up or repayment received.
    Called by Stripe webhook (payment_intent.succeeded) and repayment confirm.
    """
    client_id   = payload.get("clientId")
    company_id  = payload.get("companyId")
    amount_mxn  = float(payload.get("amountMXN", 0))
    credit_type = payload.get("type", "top_up")   # top_up | repayment_received

    result = _sp_wallet({
        "action": "credit",
        "clientId": int(client_id),
        "companyId": int(company_id),
        "amountMXN": amount_mxn,
        "creditType": credit_type,
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    })
    return JSONResponse({"wallet": result}, status_code=200)


async def debit_wallet(payload: dict):
    """
    Debit the wallet after a disbursement to a borrower.
    Called after stripe/disburse succeeds.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    amount_mxn = float(payload.get("amountMXN", 0))
    debit_type = payload.get("type", "disbursement")   # disbursement | withdrawal

    result = _sp_wallet({
        "action": "debit",
        "clientId": int(client_id),
        "companyId": int(company_id),
        "amountMXN": amount_mxn,
        "debitType": debit_type,
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    })

    if result.get("error"):
        return JSONResponse({"error": result["error"]}, status_code=400)

    return JSONResponse({"wallet": result}, status_code=200)


async def reserve_wallet(payload: dict):
    """
    Reserve funds when a proposal is accepted (before disbursement completes).
    Moves amount from availableBalance → reservedBalance.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    amount_mxn = float(payload.get("amountMXN", 0))

    result = _sp_wallet({
        "action": "reserve",
        "clientId": int(client_id),
        "companyId": int(company_id),
        "amountMXN": amount_mxn,
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    })

    if result.get("error"):
        return JSONResponse({"error": result["error"]}, status_code=400)

    return JSONResponse({"wallet": result}, status_code=200)


async def release_wallet(payload: dict):
    """
    Undo a prior reserve() when the disbursement it was held for fails.
    Moves amount from reservedBalance back to availableBalance without
    touching totalDisbursed, since no money actually moved.
    """
    client_id  = payload.get("clientId")
    company_id = payload.get("companyId")
    amount_mxn = float(payload.get("amountMXN", 0))

    result = _sp_wallet({
        "action": "release",
        "clientId": int(client_id),
        "companyId": int(company_id),
        "amountMXN": amount_mxn,
        "updatedAt": datetime.now(timezone.utc).isoformat(),
    })

    if result.get("error"):
        return JSONResponse({"error": result["error"]}, status_code=400)

    return JSONResponse({"wallet": result}, status_code=200)


async def get_all_wallets(payload: dict):
    """List all wallets for a company (admin view)."""
    company_id = payload.get("companyId")
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_clientWallets] @pjsonfile = %s",
            (json.dumps({"wallets": [{"action": "list", "companyId": int(company_id)}]}),)
        )
        rows = cursor.fetchall()
        json_result = "".join(r[0] for r in rows if r and r[0])
        return JSONResponse(json.loads(json_result) if json_result else {"wallets": []}, status_code=200)
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
