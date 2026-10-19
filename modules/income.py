import asyncio
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json

from modules.journalEntries import post_income_journal_entry, post_income_commission_journal_entry
from modules.notificationDispatch import dispatch_notification_connector
from modules.rewards import earn_points_for_income
from modules.posRewards import earn_and_summarize, rewards_label
from modules.incomePayments import record_income_payments
from modules.receiptLinks import receipt_link

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
        if not phone:
            return None
        # Stored numbers are often 10-digit local MX; providers need E.164.
        from modules.users import _normalize_phone
        return _normalize_phone(phone)
    except Exception as e:
        print(f"[income] client phone lookup failed: {e}")
        return None


def _get_final_total(conn, income_id, company_id) -> float | None:
    """sp_income_applyDiscounts can recompute total server-side (coupon /
    reward) after the initial insert -- read back the authoritative value so notifications
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


def _reverse_redemptions(conn, income_id) -> dict:
    """sp_posRewardRedemptions_reverseForIncome: a deleted sale's reward is
    cancelled (stamps count again) and its points credited back."""
    cur = conn.cursor()
    cur.execute("EXEC sp_posRewardRedemptions_reverseForIncome @incomeId = %s", (int(income_id),))
    row = cur.fetchone()
    return dict(zip(("redemptionsCancelled", "pointsRefunded"), row)) if row else {}


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


def sale_message(json_file: dict) -> str:
    """Customer message for a sale: total, discount (if any) and the POS
    rewards line (if any), one item per line. The ticket link is added by the
    dispatch connector (free-form text) or the comprobante_listo template.
        {"total": 120.0, "discountAmount": 10.0, "promoCode": "X", "rewardsLine": "..."}"""
    total = json_file.get("total")
    discount_amount = json_file.get("discountAmount")
    promo_code = json_file.get("promoCode")
    rewards_line = json_file.get("rewardsLine") or ""
    lines = [f"Gracias por su compra. Total: ${total:,.2f} MXN"
             if isinstance(total, (int, float)) else "Gracias por su compra."]
    if isinstance(discount_amount, (int, float)) and discount_amount > 0:
        code_suffix = f" ({promo_code})" if promo_code else ""
        lines.append(f"Descuento aplicado{code_suffix}: -${discount_amount:,.2f} MXN")
    if rewards_line:
        lines.append(rewards_line)
    return "\n".join(lines)


def _take_discounts(json_file: dict) -> tuple[str | None, list]:
    """Removes a new sale's coupon code and loyalty rewards from the payload
    before sp_income sees it: they're applied afterwards by
    sp_income_applyDiscounts from dbo.posRewardCatalogItems (the single
    discount table). sp_income's own B2G1 block reads the retired
    dbo.promotions, so it must never get a promotionCode."""
    row = (json_file.get("income") or [{}])[0] or {}
    if str(row.get("action")) != "1":
        return None, []
    code = (row.pop("promotionCode", None) or "").strip().upper() or None
    reward_ids = [int(i) for i in (row.pop("rewardCatalogItemIds", None) or []) if str(i).strip().isdigit()]
    return code, reward_ids


def _apply_discounts(conn, company_id, income_id, user_id, coupon_code, reward_ids) -> dict | None:
    """Coupon + reward on the saved sale; returns {total, discountAmount,
    promotionCode, applied, rejected} (sql/sp_income_applyDiscounts.sql)."""
    cur = conn.cursor()
    cur.execute("EXEC sp_income_applyDiscounts @pjsonfile = %s", (json.dumps({"incomeDiscounts": [{
        "companyId": company_id, "incomeId": income_id, "userId": user_id,
        "couponCode": coupon_code, "rewardCatalogItemIds": reward_ids}]}),))
    rows = cur.fetchall()
    raw = "".join((r[0] or "") for r in rows).strip() if rows else ""
    parsed = json.loads(raw) if raw else {}
    if parsed.get("error"):
        print(f"[income] applyDiscounts failed for income {income_id}: {parsed['error']}")
        return None
    return (parsed.get("result") or [None])[0]


def _take_request_key(json_file: dict) -> str | None:
    """Removes the POS's idempotency key (one UUID per checkout attempt, the
    same on every retry) from the payload. Only a new sale with a companyId
    uses it; dbo.income.clientRequestId is NVARCHAR(64)
    (sql/migrations/2026-10-18c_income_client_request_id.sql)."""
    row = (json_file.get("income") or [{}])[0] or {}
    key = str(row.pop("clientRequestId", None) or "").strip()
    if not key or str(row.get("action")) != "1" or not row.get("companyId"):
        return None
    if len(key) > 64:
        print(f"[income] clientRequestId longer than 64 chars ignored: {key[:64]}...")
        return None
    return key


def _lock_request_key(conn, company_id, key) -> None:
    """Serializes concurrent retries of one checkout: the second waits here
    until the first has stored its key, then finds that sale. Owned by the
    session, so it's released by _unlock_request_key or when conn closes."""
    cur = conn.cursor()
    cur.execute("DECLARE @r INT; EXEC @r = sp_getapplock @Resource = %s, @LockMode = 'Exclusive', "
                "@LockOwner = 'Session', @LockTimeout = 15000; SELECT @r",
                (f"income:{int(company_id)}:{key}",))
    row = cur.fetchone()
    if not row or row[0] is None or int(row[0]) < 0:
        # The unique index still catches the duplicate in _store_request_key.
        print(f"[income] request lock not granted ({row[0] if row else None}) for {key}")


def _unlock_request_key(conn, company_id, key) -> None:
    try:
        conn.cursor().execute("EXEC sp_releaseapplock @Resource = %s, @LockOwner = 'Session'",
                              (f"income:{int(company_id)}:{key}",))
    except Exception as e:
        print(f"[income] request lock release failed: {e}")


def _find_request(conn, company_id, key) -> int | None:
    cur = conn.cursor()
    cur.execute("SELECT incomeId FROM dbo.income WHERE companyId = %s AND clientRequestId = %s",
                (int(company_id), key))
    row = cur.fetchone()
    return int(row[0]) if row else None


def _store_request_key(conn, income_id, key) -> None:
    conn.cursor().execute("UPDATE dbo.income SET clientRequestId = %s WHERE incomeId = %s AND clientRequestId IS NULL",
                          (key, int(income_id)))


def _is_duplicate_key(e: Exception) -> bool:
    code = e.args[0] if e.args and isinstance(e.args[0], int) else None
    return code in (2601, 2627) or "duplicate key" in str(e).lower()


def _replayed_sale(conn, income_id, company_id) -> JSONResponse:
    """The response of the sale a retry already created, in the shape of an
    insert, so the POS carries on as if this call had inserted it."""
    row = {"value": str(income_id), "msg": "Inserted Successfully", "error": "0"}
    total, discount_amount, promo_code = _get_final_total_and_discount(conn, income_id, company_id)
    if discount_amount and total is not None:
        # Same keys as sp_income_applyDiscounts' result (CartPage reads
        # rejected); what was applied/rejected isn't kept, only the totals.
        row["discounts"] = {"incomeId": income_id, "subtotal": total + discount_amount, "total": total,
                            "discountAmount": discount_amount, "promotionCode": promo_code,
                            "applied": [], "rejected": []}
    print(f"[income] retried request returned existing income {income_id}")
    return JSONResponse(content={"result": [row]}, status_code=200)


def income_sp(json_file: dict):
    conn = None
    try:
        conn = connection()
        cursor = conn.cursor()
        coupon_code, reward_ids = _take_discounts(json_file)
        request_key = _take_request_key(json_file)
        request_company_id = ((json_file.get("income") or [{}])[0] or {}).get("companyId")

        # Idempotent insert: a retry of a checkout that already made a sale
        # gets that sale back and runs none of the hooks below again.
        if request_key:
            try:
                _lock_request_key(conn, request_company_id, request_key)
                existing_id = _find_request(conn, request_company_id, request_key)
            except Exception as e:
                # e.g. the 2026-10-18c migration hasn't run: sell as before.
                print(f"[income] request key lookup failed, inserting without it: {e}")
                request_key, existing_id = None, None
            if existing_id:
                return _replayed_sale(conn, existing_id, request_company_id)

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

            # Store the key before any hook runs. A duplicate here means a
            # concurrent retry stored it first (lock not granted): this row is
            # a second copy of that sale, so delete it and return the first.
            if request_key:
                try:
                    if is_new_income:
                        _store_request_key(conn, int(result[0]["value"]), request_key)
                except Exception as e:
                    existing_id = _find_request(conn, request_company_id, request_key) if _is_duplicate_key(e) else None
                    if not existing_id:
                        print(f"[income] storing clientRequestId failed: {e}")
                    else:
                        duplicate_id = int(result[0]["value"])
                        undo = conn.cursor()
                        undo.execute("EXEC sp_income @pjsonfile = %s", (json.dumps({"income": [{
                            "action": 2, "incomeId": duplicate_id, "companyId": request_company_id}]}),))
                        undo.fetchall()
                        print(f"[income] deleted duplicate income {duplicate_id} of request {request_key}")
                        return _replayed_sale(conn, existing_id, request_company_id)
                finally:
                    _unlock_request_key(conn, request_company_id, request_key)

            # Coupon + loyalty reward, priced server-side. Runs before every
            # hook below so they all use the authoritative total. The sale is
            # already saved: a failure here leaves the total the POS sent.
            if is_new_income and (coupon_code or reward_ids):
                try:
                    discounts = _apply_discounts(conn, first_row.get("companyId"), int(result[0]["value"]),
                                                 first_row.get("userId"), coupon_code, reward_ids)
                    if discounts:
                        result[0]["discounts"] = discounts
                        if discounts.get("total") is not None:
                            first_row["total"] = discounts["total"]
                except Exception as e:
                    print(f"[income] discounts hook failed: {e}")

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

            # Best-effort: record the payment-method breakdown for a split
            # sale (e.g. 60% Efectivo + 40% Tarjeta) -- only present when the
            # frontend sent a "payments" array (CartPage.tsx's split-payment
            # mode); a normal single-method sale sends nothing here and this
            # is a no-op. See modules/incomePayments.py for the known gap:
            # the card-terminal commission hook below does not yet journal
            # a split sale's Tarjeta portion.
            try:
                if is_new_income and first_row.get("payments"):
                    record_income_payments(int(result[0]["value"]), first_row.get("payments"))
            except Exception as e:
                print(f"[income] split-payment record hook failed: {e}")

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
                    # The reward the sale used comes back first, so taking
                    # back its earned points sees the refunded balance.
                    try:
                        given_back = _reverse_redemptions(conn, first_row.get("incomeId"))
                        print(f"[income] gave back rewards of deleted income {first_row.get('incomeId')}: {given_back}")
                    except Exception as e:
                        print(f"[income] reward give-back failed: {e}")
                    reversal = _reverse_on_delete(conn, first_row.get("incomeId"))
                    print(f"[income] reversed deleted income {first_row.get('incomeId')}: {reversal}")
            except Exception as e:
                print(f"[income] delete reversal hook failed: {e}")

            # Best-effort: fire the Push -> WhatsApp -> SMS cascade for the
            # client on a successful income. Never blocks/fails the income
            # response. This is the ONLY customer notification for a sale:
            # printing the ticket (useReceiptPrint.ts) no longer dispatches,
            # so one income = one dispatch (income_created).
            try:
                if is_new_income:
                    company_id = first_row.get("companyId")
                    client_id = first_row.get("clientId")
                    income_id = int(result[0]["value"])
                    # Walk-in ("mostrador", clientId 1) sales notify no one.
                    if company_id and client_id and str(client_id) != "1":
                        phone = _get_client_phone(conn, client_id)
                        final_total, discount_amount, promo_code = _get_final_total_and_discount(conn, income_id, company_id)
                        if final_total is None:
                            final_total = first_row.get("total")
                        # POS points are posted HERE, before the message is
                        # built, so the message can say what this sale earned.
                        # Idempotent: the cart's later earnFromTicket replays it.
                        rewards_line = rewards_label(earn_and_summarize({"posRewardTransactions": [
                            {"companyId": int(company_id), "clientId": int(client_id), "incomeId": income_id}]}))
                        preview = sale_message({
                            "total": final_total, "discountAmount": discount_amount,
                            "promoCode": promo_code, "rewardsLine": rewards_line,
                        })
                        asyncio.run(dispatch_notification_connector({
                            "companyId": company_id,
                            "sourceType": "income",
                            "sourceId": income_id,
                            "recipientType": "client",
                            "recipientId": client_id,
                            "eventName": "income_created",
                            "phone": phone,
                            "pushTitle": "Ingreso recibido",
                            "messagePreview": preview,
                            # Signed /recibo link (None if RECEIPT_LINK_SECRET is unset →
                            # the message goes out without a link, as before).
                            "receiptUrl": receipt_link(company_id, income_id),
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