from fastapi.responses import JSONResponse
from databases import connection
import asyncio
import json
import threading


def _conn():
    return connection()


def proposal_notices(item: dict, before: dict | None, result: dict) -> list[tuple]:
    """Core pushes (modules/loanPush) for one sp_loanProposals call — pure, so
    the rules are testable. Returns [(clientId, template, params), ...].

    create (1)                       -> lender:   loan_requested
    update (2) to 'accepted'         -> borrower: loan_approved_borrower, lender: loan_approved_lender
    update to 'countered'            -> borrower: loan_countered (with the countered terms)
    update 'countered' -> 'pending'  -> lender:   loan_counter_accepted
    update 'countered' -> 'rejected' -> lender:   loan_counter_rejected
    update other -> 'rejected'       -> borrower: loan_rejected
    """
    action = item.get("action")
    if action == 1:
        if not result.get("proposalId"):
            return []
        return [(result.get("lenderId"), "loan_requested", {
            "name": item.get("borrowerName") or "Un acreditado",
            "amount": result.get("requestedAmount"), "rate": result.get("proposedRate"),
            "term": result.get("termMonths"), "proposalId": result.get("proposalId")})]
    if action != 2 or not before or "error" in result:
        return []
    new_status, old_status = item.get("status"), before.get("status")
    if not new_status or new_status == old_status and new_status != "accepted":
        return []
    lender, borrower = before.get("lenderId"), before.get("borrowerId")
    terms = {
        "amount": item.get("counteredAmount") or before.get("counteredAmount") or before.get("requestedAmount"),
        "rate": item.get("counteredRate") or before.get("counteredRate") or before.get("proposedRate"),
        "term": item.get("counteredTermMonths") or before.get("counteredTermMonths") or before.get("termMonths"),
        "proposalId": before.get("proposalId"),
    }
    if new_status == "accepted":
        return [(borrower, "loan_approved_borrower", terms), (lender, "loan_approved_lender", terms)]
    if new_status == "countered":
        return [(borrower, "loan_countered", terms)]
    if new_status == "pending" and old_status == "countered":
        return [(lender, "loan_counter_accepted", terms)]
    if new_status == "rejected":
        if old_status == "countered":
            return [(lender, "loan_counter_rejected", terms)]
        return [(borrower, "loan_rejected", {**terms, "amount": before.get("requestedAmount")})]
    return []


def _proposal_before(item: dict) -> dict | None:
    if item.get("action") != 2 or not item.get("proposalId"):
        return None
    try:
        data = json.loads(one_loan_proposal_sp({"loanProposals": [{"proposalId": item["proposalId"]}]}).body)
        rows = data.get("loanProposals") or []
        return rows[0] if rows else None
    except Exception as e:
        print(f"[loanProposals] could not read proposal before update: {e}")
        return None


def _borrower_name(client_id) -> str:
    try:
        from modules.loanOffers import _offer_contact
        name = (_offer_contact(client_id) or {}).get("name") or ""
        return name if name and name != "prestamista" else "Un acreditado"
    except Exception:
        return "Un acreditado"


def _send_proposal_notices(item: dict, before: dict | None, result: dict) -> None:
    """Background: name lookup + one core push per notice (never raises)."""
    try:
        company_id = item.get("companyId") or (before or {}).get("companyId") or result.get("companyId")
        if item.get("action") == 1 and result.get("proposalId"):
            item = {**item, "borrowerName": _borrower_name(result.get("borrowerId"))}
        from modules.loanPush import push_to_client
        for client_id, template, params in proposal_notices(item, before, result):
            asyncio.run(push_to_client(company_id, client_id, template, **params))
    except Exception as e:
        print(f"[loanProposals] push failed: {e}")


def loan_proposals_sp(json_file: dict):
    """CRUD for loanProposals via sp_loanProposals (action 1=create, 2=update, 3=delete).
    Each create/transition pushes the other party (RFC-014 core push, loanPush),
    in the background — the response never waits on it."""
    item = (json_file.get("loanProposals") or [{}])[0] if isinstance(json_file, dict) else {}
    before = _proposal_before(item)
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
        result = json.loads(json_result)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()

    if isinstance(result, dict):
        threading.Thread(target=_send_proposal_notices, args=(item, before, result), daemon=True).start()

    return JSONResponse(content=result, status_code=200)


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
