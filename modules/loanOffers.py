from fastapi.responses import JSONResponse
from databases import connection
import json


def _conn():
    return connection()


def loan_offers_sp(json_file: dict):
    """CRUD for loanOffers via sp_loanOffers (action 1=create, 2=update/close, 3=delete)."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanOffers] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        row = cursor.fetchone()
        json_result = row[0] if row and row[0] else '{"message": "ok"}'
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_loan_offers_sp(json_file: dict):
    """List active/all loanOffers by companyId."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanOffers_all] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        rows = cursor.fetchall()
        json_result = "".join(r[0] for r in rows if r and r[0])
        if not json_result:
            return JSONResponse(content={"loanOffers": []}, status_code=200)
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def one_loan_offer_sp(json_file: dict):
    """Fetch a single loanOffer by offerId."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanOffers_one] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        row = cursor.fetchone()
        json_result = row[0] if row and row[0] else '{"loanOffers": []}'
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
