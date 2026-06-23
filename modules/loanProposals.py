from fastapi.responses import JSONResponse
from databases import connection
import json


def _conn():
    return connection()


def loan_proposals_sp(json_file: dict):
    """CRUD for loanProposals via sp_loanProposals (action 1=create, 2=update, 3=delete)."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanProposals] @pjsonfile = %s",
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


def all_loan_proposals_sp(json_file: dict):
    """List loanProposals filtered by companyId, lenderId, borrowerId, status."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanProposals_all] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        rows = cursor.fetchall()
        json_result = "".join(r[0] for r in rows if r and r[0])
        if not json_result:
            return JSONResponse(content={"loanProposals": []}, status_code=200)
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def one_loan_proposal_sp(json_file: dict):
    """Fetch a single loanProposal by proposalId."""
    conn = None
    try:
        conn = _conn()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanProposals_one] @pjsonfile = %s",
            (json.dumps(json_file),)
        )
        row = cursor.fetchone()
        json_result = row[0] if row and row[0] else '{"loanProposals": []}'
        return JSONResponse(content=json.loads(json_result), status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
