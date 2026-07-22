from fastapi.responses import JSONResponse
from databases import connection
import json


def _match_lenders(company_id: int, amount: float) -> list[dict]:
    """MVP matching: lenders whose wallet availableBalance covers the
    requested amount. Risk-profile/state/country matching needs new
    columns on dbo.clients before it can be added here."""
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loans_matchLenders] @pjsonfile = %s",
            (json.dumps({"companyId": company_id, "amount": amount}),),
        )
        row = cursor.fetchone()
        return json.loads(row[0]) if row and row[0] else []
    except Exception as e:
        print(f"[loans] _match_lenders failed: {e}")
        return []
    finally:
        if conn:
            conn.close()


async def _notify_matching_lenders(loan: dict) -> None:
    """Pushes 'new loan request' to every matched lender — Step 1 of the
    SmartLoans lending flow (1 borrower -> N lenders, notification only,
    no chat yet)."""
    from modules.pushNotifications import pushNotifications_sp

    company_id = loan.get("companyId")
    amount = loan.get("principalAmount", 0)
    loan_number = loan.get("loanNumber", "")

    lenders = _match_lenders(company_id, amount)
    for lender in lenders:
        target_user_id = lender.get("userId")
        if not target_user_id:
            continue
        try:
            await pushNotifications_sp({
                "pushNotifications": [{
    "action": 1,
                    "companyId": company_id,
                    "title": "💰 Nueva solicitud de préstamo",
                    "message": f"Préstamo {loan_number}: ${amount:,.2f} MXN disponible para financiar.",
                    "notificationType": "Info",
                    "priority": "High",
                    "targetType": "User",
                    "targetUserId": target_user_id,
                    "navigationRoute": "/loan-chat/new",
                }]
            })
        except Exception as e:
            print(f"[loans] notify lender userId={target_user_id} failed: {e}")


def loans_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_loans] @pjsonfile = %s", (json.dumps(json_file),))
        json_result = cursor.fetchall()
        # SP returns ONE row, ONE column ([jsonResult]) -> [0][0], NEVER [0][1]
        result = json.loads(json_result[0][0])
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_loans_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_loans_all] @pjsonfile = %s", (json.dumps(json_file),))
        rows = cursor.fetchall()
        json_result = "".join(row[0] for row in rows)
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def one_loans_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_loans_one] @pjsonfile = %s", (json.dumps(json_file),))
        row = cursor.fetchone()
        json_result = row[0] if row else "{}"
        result = json.loads(json_result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
