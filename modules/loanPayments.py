from fastapi.responses import JSONResponse
from databases import connection
import json
import os
from decimal import Decimal
from observability import log_audit, workflow_step
from modules.azure_notifications import send_azure_push
from security.session_tokens import resolve_push_user_ids


def _sp(payload: dict):
    conn = cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_loanPayments] @pjsonfile = %s",
            (json.dumps({"loanPayments": [payload]}),)
        )
        row = cursor.fetchone()
        raw = row[0] if row and row[0] else "null"
        # TIER_2_FINANCIAL: parse decimals without float conversion
        return json.loads(raw, parse_float=Decimal) if isinstance(raw, str) else raw
    except Exception as e:
        return {"error": str(e)}
    finally:
        try:
            if cursor: cursor.close()
        except Exception: pass
        try:
            if conn: conn.close()
        except Exception: pass


async def loanPayments_sp(payload: dict):
    action = payload.get("action", "")
    loan_payment_id = payload.get("loanPaymentId") # Used for logging and push targets
    company_id = payload.get("companyId", 0)

    # Use workflow_step for multi-step or significant actions
    with workflow_step(f"LoanPayment {action}", workflow_name="LoanRepaymentProcess"):
        result = _sp(payload)

        if isinstance(result, dict) and "error" in result:
            # Log only the action and relevant IDs, not sensitive data
            log_audit("loanPayments", loan_payment_id, "action", None, action, action="failed")
            return JSONResponse(content=result, status_code=400)

        # Process result for push notifications and audit logging
        # Assuming result contains the updated state or confirmation data
        if isinstance(result, dict) and "loanPayments" in result and result["loanPayments"]:
            final_state = result["loanPayments"][0]
            loan_payment_id = final_state.get("loanPaymentId") # Update if it was an insert (declare)
            current_status = final_state.get("status")
            payer_client_id = final_state.get("payerClientId")
            payee_client_id = final_state.get("payeeClientId")

            # Audit logging for mutations
            if action in ["declare", "confirm", "reject", "cancel", "resolve_escalation"]:
                log_audit("loanPayments", loan_payment_id, "status", None, current_status, action="update")

            # Push notifications based on action and roles
            if action == "declare":
                target_client_id = payee_client_id
                push_title = "Pago Declarado"
                push_body = f"Se ha declarado un pago de {final_state.get('amountMXN', Decimal(0)):.2f} MXN para su préstamo."
            elif action in ["confirm", "reject", "resolve_escalation"]:
                target_client_id = payer_client_id
                if action == "confirm":
                    push_title = "Pago Confirmado"
                    push_body = f"Su pago de {final_state.get('amountMXN', Decimal(0)):.2f} MXN ha sido confirmado."
                elif action == "reject":
                    push_title = "Pago Rechazado"
                    push_body = f"Su pago de {final_state.get('amountMXN', Decimal(0)):.2f} MXN ha sido rechazado: {final_state.get('rejectReason', 'Motivo no especificado')}."
                else: # resolve_escalation
                    push_title = "Caso Resuelto"
                    push_body = f"La escalación de su pago de {final_state.get('amountMXN', Decimal(0)):.2f} MXN ha sido resuelta."
            else:
                target_client_id = None

            if target_client_id:
                # Resolve client ID to user ID for push notification targeting
                user_ids = await resolve_push_user_ids([target_client_id], company_id=company_id) # company_id needed for context
                if user_ids:
                    for user_id in user_ids:
                        await send_azure_push(
                            user_id=user_id,
                            title=push_title,
                            body=push_body,
                            data={
                                "action": action,
                                "loanPaymentId": loan_payment_id,
                                "companyId": company_id,
                                "status": current_status
                            },
                        )
        # For 'list', 'one', 'statement', 'escalate_due' (returning arrays), no specific push needed here.

        return JSONResponse(content=result, status_code=200)
