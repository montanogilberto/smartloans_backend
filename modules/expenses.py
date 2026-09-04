from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json
import uuid
from datetime import datetime

from modules.clientFaceRecognitions import (
    _upload_base64_to_blob, company_blob_path, BLOB_FOLDER_EXPENSE_RECEIPTS,
)
from observability import log_workflow_step, log_audit
from observability.integrations import timed_integration
from modules.journalEntries import post_expense_journal_entry

app = FastAPI()

# sp_expense action codes -> a human label for workflow/audit logs.
_ACTION_LABELS = {1: "Insert", 2: "Update", 3: "Delete"}


def expense_sp(json_file: dict):
    conn = None
    try:
        expenses_in = (json_file or {}).get("expenses") or [{}]
        first_in = expenses_in[0] if expenses_in else {}
        action = first_in.get("action")
        total = first_in.get("total")
        expense_id_in = first_in.get("expenseId")

        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_expense @pjsonfile = %s", (json.dumps(json_file),))

        # Obtener resultado en formato JSON
        result_row = cursor.fetchall()

        if result_row:
            result = []
            for row in result_row:
                result.append({
                    "value": row[0],
                    "msg": row[1],
                    "error": row[2]
                })

            # money_trail: same workflow_name used by transfers.py / stripe_payments.py
            # for every other money-moving mutation in this backend.
            first_out = result[0] if result else {}
            failed = str(first_out.get("error") or "") == "1"
            entity_id_raw = expense_id_in or first_out.get("value")
            entity_id = int(entity_id_raw) if str(entity_id_raw or "").isdigit() else None
            action_label = _ACTION_LABELS.get(action, "Mutation")

            log_workflow_step(
                f"Expense {action_label}",
                workflow_name="money_trail",
                action=action_label.upper(),
                status="FAILED" if failed else "SUCCESS",
                entity="expenses",
                entity_id=entity_id,
                message=first_out.get("msg") or (
                    f"${total:,.2f} MXN" if isinstance(total, (int, float)) else None
                ),
            )

            if not failed and action in (1, 2) and entity_id is not None:
                log_audit(
                    "expenses", entity_id, "total", None, total,
                    action="INSERT" if action == 1 else "UPDATE",
                )

            # Best-effort: mirror a successful INSERT into the ledger (Módulo
            # Contabilidad), regardless of expenseType. Never blocks/fails the
            # expense response — see modules/journalEntries.py::post_expense_journal_entry.
            if not failed and action == 1 and entity_id is not None:
                try:
                    company_id = first_in.get("companyId")
                    if company_id and total:
                        post_expense_journal_entry(company_id, entity_id, float(total), first_in.get("paymentDate"))
                except Exception as e:
                    print(f"[expenses] accounting auto-post hook failed: {e}")

            return JSONResponse(content={"result": result}, status_code=200)
        else:
            return JSONResponse(content={"result": [], "msg": "No data returned"}, status_code=204)

    except Exception as e:
        log_workflow_step(
            "Expense Mutation Error", workflow_name="money_trail",
            status="FAILED", entity="expenses", message=str(e),
        )
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


async def upload_expense_receipt_connector(payload: dict) -> JSONResponse:
    """Uploads a photo of a physical receipt/ticket (evidence of an expense)
    to Azure Blob Storage -- same helpers/container as clientFaceRecognitions
    and transferEvidence, just a company-scoped folder instead of client-scoped.
    Returns: { blobUrl }. The caller persists the URL via sp_expense
    action=1/2 (receiptUrl) separately -- this endpoint only uploads bytes."""
    try:
        company_id = payload.get("companyId", "0")
        image_b64  = payload.get("imageBase64", "")

        if not image_b64:
            return JSONResponse(content={"error": "imageBase64 is required"}, status_code=400)

        ts  = datetime.utcnow().strftime("%Y%m%d%H%M%S")
        uid = str(uuid.uuid4())[:8]
        blob_path = company_blob_path(company_id, BLOB_FOLDER_EXPENSE_RECEIPTS, f"receipt_{ts}_{uid}.jpg")

        with timed_integration(
            "azure_blob", "upload_expense_receipt",
            request={"companyId": str(company_id), "blobPath": blob_path},
        ) as span:
            blob_url = _upload_base64_to_blob(
                image_b64, blob_path, "image/jpeg",
                {"companyId": str(company_id)},
            )
            span.response = {"blobUrl": blob_url}
            span.http_status = 200

        return JSONResponse(content={"blobUrl": blob_url}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def all_expense_sp():
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_expense_all]")

        # Fetch all the results as a list of tuples
        rows = cursor.fetchall()

        # Concatenate JSON strings from all rows into one string
        json_result = "".join(row[0] for row in rows)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()
