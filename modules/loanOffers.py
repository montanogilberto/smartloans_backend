from fastapi.responses import JSONResponse
from databases import connection
from datetime import datetime
import json
import threading


def _conn():
    return connection()


def _offer_contact(client_id) -> dict:
    """Email/teléfono/nombre del lender para el ticket de "capital publicado"
    — lectura directa, best-effort (un fallo aquí nunca afecta la respuesta
    de publishOffer)."""
    conn = None
    try:
        conn = connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT email, cellphone, first_name, last_name FROM dbo.clients WHERE clientId = %s",
            (client_id,))
        row = cur.fetchone()
        if not row:
            return {}
        return {
            "email": (row[0] or "").strip(),
            "cellphone": (row[1] or "").strip(),
            "name": f"{row[2] or ''} {row[3] or ''}".strip() or "prestamista",
        }
    except Exception as e:
        print(f"[loanOffers][ticket] client lookup FAILED: {e}")
        return {}
    finally:
        if conn:
            conn.close()


def _send_offer_published_ticket(offer: dict):
    """Ticket de "capital publicado" por email + WhatsApp. Corre en un hilo
    aparte, best-effort — nunca afecta la respuesta de loan_offers_sp.
    WhatsApp usa mensaje freeform (sin Content Template aprobado): si el
    lender no le ha escrito al número de SmartLoans en las últimas 24h,
    Twilio rechaza con error 63016 — se loguea, no se reintenta ni bloquea
    el email (ver memoria de proyecto "WhatsApp sender & 24h window")."""
    try:
        client_id = offer.get("lenderId")
        if not client_id:
            return
        contact = _offer_contact(client_id)
        capital = float(offer.get("availableCapital", 0))
        folio = offer.get("offerId") or "—"
        fecha = datetime.utcnow().strftime("%d/%m/%Y %H:%M UTC")
        descripcion = offer.get("description") or ""

        lineas = [
            f"Hola {contact.get('name', 'prestamista')},",
            "",
            "Tu capital disponible fue publicado en SmartLoans.",
            "",
            f"Folio:             {folio}",
            f"Capital declarado: ${capital:,.2f} MXN",
            f"Fecha y hora:      {fecha}",
        ]
        if descripcion:
            lineas.append(f"Descripción:       {descripcion}")
        lineas += [
            "",
            "Este es un comprobante de tu declaración de capital, no un movimiento de dinero.",
            "SmartLoans no recibe, retiene ni administra estos fondos — el monto, la tasa y el",
            "plazo se acuerdan directamente con el solicitante cuando aceptes una propuesta.",
            "",
            "— SmartLoans · POS GMO",
        ]
        body_text = "\n".join(lineas)

        email = contact.get("email") or ""
        if "@" in email:
            try:
                from modules.users import _send_email
                subject = f"SmartLoans — Capital publicado ${capital:,.2f} MXN (folio {folio})"
                _send_email(email, subject, body_text)
                print(f"[loanOffers][ticket] email ENVIADO a {email} folio={folio}")
            except Exception as e:
                print(f"[loanOffers][ticket] email FAILED (non-fatal): {type(e).__name__}: {e}")
        else:
            print(f"[loanOffers][ticket] clientId={client_id} sin email — ticket por correo omitido")

        cellphone = contact.get("cellphone") or ""
        if cellphone:
            try:
                from modules.users import _normalize_phone
                from modules.ticket_notifications import send_whatsapp
                wa_body = (
                    f"SmartLoans: publicaste ${capital:,.2f} MXN de capital disponible "
                    f"(folio {folio}). No implica transferir ni bloquear fondos."
                )
                send_whatsapp(_normalize_phone(cellphone), wa_body)
                print(f"[loanOffers][ticket] whatsapp ENVIADO a {cellphone} folio={folio}")
            except Exception as e:
                # 63016 esperado si el lender está fuera de la ventana de 24h
                # y no existe Content Template aprobado todavía — ver memoria.
                print(f"[loanOffers][ticket] whatsapp FAILED (non-fatal): {type(e).__name__}: {e}")
        else:
            print(f"[loanOffers][ticket] clientId={client_id} sin cellphone — ticket por WhatsApp omitido")
    except Exception as e:
        print(f"[loanOffers][ticket] FAILED (non-fatal): {type(e).__name__}: {e}")


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
        result = json.loads(json_result)

        action = (json_file.get("loanOffers") or [{}])[0].get("action")
        if action == 1 and isinstance(result, dict) and result.get("offerId") and "error" not in result:
            # Ticket por email + WhatsApp en un hilo aparte — no retrasa la
            # respuesta (mismo patrón que el comprobante Stripe, ver
            # modules/stripe_payments.py:_send_transaction_receipt_email).
            threading.Thread(
                target=_send_offer_published_ticket,
                args=(result,),
                daemon=True,
            ).start()

        return JSONResponse(content=result, status_code=200)
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
