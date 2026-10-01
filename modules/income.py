import asyncio
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

from modules.journalEntries import post_income_journal_entry, post_income_commission_journal_entry
from modules.notificationDispatch import dispatch_notification_connector
from modules.rewards import earn_points_for_income

app = FastAPI()


def _get_client_phone(conn, client_id) -> str | None:
    try:
        cur = conn.cursor()
        cur.execute("EXEC sp_clients_one @pjsonfile = %s",
                    (json.dumps({"clients": [{"clientId": client_id}]}),))
        # FOR JSON AUTO may split the payload across several rows
        rows = cur.fetchall()
        json_text = "".join((r[0] or "") for r in rows).strip() if rows else ""
        if not json_text:
            return None
        clients = json.loads(json_text).get("clients") or []
        phone = (clients[0].get("cellphone") or "").strip() if clients else ""
        return phone or None
    except Exception as e:
        print(f"[income] client phone lookup failed: {e}")
        return None


def _get_final_total(conn, income_id, company_id) -> float | None:
    """sp_income can recompute total server-side (B2G1 promo) after the
    initial insert -- read back the authoritative value so notifications
    quote the amount actually charged, not the pre-promo client-submitted one."""
    total, _discount, _promo_code = _get_final_total_and_discount(conn, income_id, company_id)
    return total


def _get_final_total_and_discount(conn, income_id, company_id) -> tuple[float | None, float | None, str | None]:
    """Same authoritative read as _get_final_total, plus whatever B2G1 promo
    discount sp_income applied -- so the comprobante message can say WHY the
    total is what it is, not just quote the post-discount number."""
    try:
        cur = conn.cursor()
        cur.execute("EXEC sp_income_one @pjsonfile = %s",
                    (json.dumps({"income": [{"incomeId": income_id, "companyId": company_id}]}),))
        # FOR JSON AUTO may split the payload across several rows
        rows = cur.fetchall()
        json_text = "".join((r[0] or "") for r in rows).strip() if rows else ""
        if not json_text:
            return None, None, None
        parsed = json.loads(json_text)
        incomes = parsed.get("income") if isinstance(parsed, dict) else None
        if not incomes:
            return None, None, None
        inc = incomes[0]
        total = float(inc["total"]) if inc.get("total") is not None else None
        discount = float(inc["discountAmount"]) if inc.get("discountAmount") is not None else None
        promo_code = inc.get("promotionCode") or None
        return total, discount, promo_code
    except Exception as e:
        print(f"[income] final total/discount lookup failed: {e}")
        return None, None, None


def _apply_terminal_commission(conn, income_id, commission_terminal_id=None) -> dict:
    """sp_income_applyCommission for one sale. Idempotent in the SP: a sale
    that already has commissionAmount is never re-priced."""
    item = {"incomeId": income_id}
    if commission_terminal_id:
        item["commissionTerminalId"] = commission_terminal_id
    cur = conn.cursor()
    cur.execute("EXEC sp_income_applyCommission @pjsonfile = %s",
                (json.dumps({"income": [item]}),))
    row = cur.fetchone()
    result = json.loads(row[0]) if row and row[0] else {}
    if "error" in result:
        raise RuntimeError(result["error"])
    return result


def _reverse_on_delete(conn, income_id) -> dict:
    """sp_income_reverseOnDelete for a sale that was just deleted (Step 5,
    2026-10-01): VOIDs its income/commission journal entries and takes back
    the points it earned. Idempotent in the SP; refuses while the sale exists."""
    cur = conn.cursor()
    cur.execute("EXEC sp_income_reverseOnDelete @incomeId = %s", (int(income_id),))
    row = cur.fetchone()
    if not row:
        return {}
    keys = ("voidedEntries", "posPointsReversed", "posPointsShortfall",
            "loyaltyPointsReversed", "loyaltyPointsShortfall", "alreadyReversed")
    return dict(zip(keys, row))


def income_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_income @pjsonfile = %s", (json.dumps(json_file),))

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

            # Best-effort: mirror a successful INSERT into the ledger (Módulo
            # Contabilidad). Never blocks/fails the income response — see
            # modules/journalEntries.py::post_income_journal_entry.
            #
            # sp_income reports success as error="0" (a non-empty, truthy
            # string), never "" -- so `not result[0].get("error")` is always
            # False and this silently never fired. Fixed to the same
            # explicit-"1"-check pattern already used correctly in
            # modules/expenses.py.
            first_row = (json_file.get("income") or [{}])[0]
            failed = result and str(result[0].get("error") or "") == "1"
            is_new_income = str(first_row.get("action")) == "1" and result and not failed
            try:
                if is_new_income:
                    company_id = first_row.get("companyId")
                    total = first_row.get("total")
                    if company_id and total:
                        post_income_journal_entry(
                            company_id, int(result[0]["value"]), float(total), first_row.get("paymentDate"),
                            payment_method=first_row.get("paymentMethod"),
                        )
            except Exception as e:
                print(f"[income] accounting auto-post hook failed: {e}")

            # Best-effort: auto-earn loyalty points for this sale, linked to
            # the real incomeId (see modules/rewards.py::earn_points_for_income
            # for why this matters -- rewardTransactions.referenceId was
            # never populated with a real incomeId before this).
            try:
                if is_new_income:
                    company_id = first_row.get("companyId")
                    client_id = first_row.get("clientId")
                    total = first_row.get("total")
                    if company_id and client_id and total:
                        earn_points_for_income(company_id, client_id, int(result[0]["value"]), total)
            except Exception as e:
                print(f"[income] rewards auto-earn hook failed: {e}")

            # Best-effort: stamp the card-terminal commission (rate snapshot +
            # amount) on the new sale so income reports show what actually
            # reaches the bank. Runs after sp_income, so it prices the final
            # (post-promo) total. Cash/transfer sales are a no-op in the SP.
            try:
                if is_new_income and str(first_row.get("paymentMethod") or "").strip().lower() in ("tarjeta", "terminal"):
                    stamped = _apply_terminal_commission(conn, int(result[0]["value"]), first_row.get("commissionTerminalId"))
                    # Step 4 (2026-10-01): the commission is a real cost that
                    # leaves Bancos — journal it (Dr 5120 / Cr 1105), same day
                    # as the sale's own entry. Best-effort like the other hooks.
                    if stamped.get("commissionAmount"):
                        post_income_commission_journal_entry(
                            first_row.get("companyId"), int(result[0]["value"]),
                            stamped["commissionAmount"], first_row.get("paymentDate"),
                        )
            except Exception as e:
                print(f"[income] terminal commission hook failed: {e}")

            # Best-effort: a deleted sale (action=2) must not keep counting in
            # the books or keep the points it earned — VOID its journal entries
            # and reverse its points (owner decision 2026-10-01; points are
            # promotional, so no journal entry is created for them).
            try:
                is_deleted_income = (str(first_row.get("action")) == "2" and result and not failed
                                     and first_row.get("incomeId"))
                if is_deleted_income:
                    reversal = _reverse_on_delete(conn, first_row.get("incomeId"))
                    print(f"[income] reversed deleted income {first_row.get('incomeId')}: {reversal}")
            except Exception as e:
                print(f"[income] delete reversal hook failed: {e}")

            # Best-effort: fire the Push -> WhatsApp -> SMS cascade for the
            # client on a successful income. Never blocks/fails the income
            # response. NOTE: this runs independently of the existing manual
            # "Imprimir" ticket flow (ticketApi.ts -> /api/tickets/.../send-*),
            # which still sends its own WhatsApp/SMS when the cashier taps
            # Imprimir -- until one of the two paths is retired, a client can
            # receive two messages for the same sale.
            try:
                if is_new_income:
                    company_id = first_row.get("companyId")
                    client_id = first_row.get("clientId")
                    income_id = int(result[0]["value"])
                    if company_id and client_id:
                        phone = _get_client_phone(conn, client_id)
                        final_total, discount_amount, promo_code = _get_final_total_and_discount(conn, income_id, company_id)
                        if final_total is None:
                            final_total = first_row.get("total")
                        preview = (
                            f"Gracias por su compra. Total: ${final_total:,.2f} MXN"
                            if isinstance(final_total, (int, float)) else "Gracias por su compra."
                        )
                        if isinstance(discount_amount, (int, float)) and discount_amount > 0:
                            code_suffix = f" ({promo_code})" if promo_code else ""
                            preview += f"\nDescuento aplicado{code_suffix}: -${discount_amount:,.2f} MXN"
                        asyncio.run(dispatch_notification_connector({
                            "companyId": company_id,
                            "sourceType": "income",
                            "sourceId": income_id,
                            "recipientType": "client",
                            "recipientId": client_id,
                            "eventName": "income_created",
                            "phone": phone,
                            "messagePreview": preview,
                        }))
            except Exception as e:
                print(f"[income] notification dispatch hook failed: {e}")

            return JSONResponse(content={"result": result}, status_code=200)
        else:
            return JSONResponse(content={"result": [], "msg": "No data returned"}, status_code=204)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()


def all_income_sp():
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_income_all]")

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


def monthly_income_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_income_monthly] @pjsonfile = %s", (json.dumps(json_file),))

        # Fetch all the results as a list of tuples
        rows = cursor.fetchall()

        # Concatenate JSON strings from all rows into one string
        json_result = "".join(row[0] for row in rows if row and row[0])

        if not json_result:
            return JSONResponse(content={"income": []}, status_code=200)

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        if conn:
            conn.close()