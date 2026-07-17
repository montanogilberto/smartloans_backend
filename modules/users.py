from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json
import smtplib
import ssl
import os
import random
import string
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("users")

app = FastAPI()

# In-memory store for email verification codes: { email: { code, expires } }
_verification_codes: dict = {}

# Gmail SMTP config — credentials from environment variables
# Set GMAIL_SENDER and GMAIL_APP_PASSWORD in Azure App Service → Configuration → App settings.
# Both must point to the SAME Google account — the App Password only works for
# the account it was generated on; a mismatched GMAIL_SENDER produces a Gmail
# 535 "Username and Password not accepted" that looks like a bad password but
# isn't. No silent default here on purpose, so a missing/wrong GMAIL_SENDER
# fails with a clear message instead of that confusing 535.
_SMTP_SERVER   = "smtp.gmail.com"
_SMTP_PORT     = 587
_SENDER_EMAIL  = os.environ.get("GMAIL_SENDER", "")
_SENDER_PWD    = os.environ.get("GMAIL_APP_PASSWORD", "")

def users_sp(json_file: dict):
    conn = None
    cursor = None
    try:
        logger.info("[users_sp] INPUT: %s", json.dumps(json_file))
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_users @pjsonfile = %s", (json.dumps(json_file),))

        # SP returns columns: value, msg, error  (not a JSON string)
        row = cursor.fetchone()
        logger.info("[users_sp] RAW ROW: %s", row)

        if row is None:
            logger.warning("[users_sp] SP returned no rows")
            return JSONResponse(content={"error": "No result from SP"}, status_code=500)

        result = {
            "userId": row[0],   # SCOPE_IDENTITY() as string on action=1
            "msg":    row[1],
            "error":  row[2],
        }
        logger.info("[users_sp] RESULT: %s", result)

        if result.get("error") and result["error"] not in (None, "", "0"):
            return JSONResponse(content=result, status_code=500)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        logger.exception("[users_sp] EXCEPTION: %s", e)
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass
        try:
            if conn:
                conn.close()
        except Exception:
            pass


def _send_email_otp(target: str, code: str):
    if not _SENDER_EMAIL:
        raise ValueError(
            "GMAIL_SENDER env var is not set. Set it to the same Gmail address "
            "the GMAIL_APP_PASSWORD was generated for, in Azure App Service → "
            "Configuration → App settings."
        )
    if not _SENDER_PWD:
        raise ValueError(
            "GMAIL_APP_PASSWORD env var is not set. "
            "Generate an App Password at https://myaccount.google.com/apppasswords "
            f"for {_SENDER_EMAIL} and add it to Azure App Service → Configuration → App settings."
        )
    from email.mime.text import MIMEText
    from email.mime.multipart import MIMEMultipart
    msg = MIMEMultipart()
    msg["From"]    = _SENDER_EMAIL
    msg["To"]      = target
    msg["Subject"] = "Código de verificación — SmartLoans"
    body = (
        f"Tu código de verificación es:\n\n"
        f"  {code}\n\n"
        f"Ingresa este código en la pantalla de registro. Expira en 10 minutos."
    )
    msg.attach(MIMEText(body, "plain", "utf-8"))
    ctx = ssl.create_default_context()
    with smtplib.SMTP(_SMTP_SERVER, _SMTP_PORT) as server:
        server.starttls(context=ctx)
        server.login(_SENDER_EMAIL, _SENDER_PWD)
        server.sendmail(_SENDER_EMAIL, target, msg.as_string())


def _normalize_phone(phone: str) -> str:
    """
    Ensure phone is in E.164 format required by Twilio.
    Accepts:  6621408769       → +526621408769  (10-digit MX local)
              526621408769     → +526621408769  (12-digit, missing +)
              +526621408769    → +526621408769  (already correct)
    """
    digits = "".join(c for c in phone if c.isdigit())
    if len(digits) == 10:
        return f"+52{digits}"
    if len(digits) == 12 and digits.startswith("52"):
        return f"+{digits}"
    if phone.strip().startswith("+"):
        return phone.strip()
    return phone  # pass through; Twilio will reject if still wrong


def _send_sms_otp(phone: str, code: str, via_whatsapp: bool = False):
    """Send OTP via Twilio SMS or WhatsApp. Requires TWILIO_* env vars."""
    account_sid = os.environ.get("TWILIO_ACCOUNT_SID", "")
    auth_token  = os.environ.get("TWILIO_AUTH_TOKEN", "")
    from_number = os.environ.get("TWILIO_FROM", "")
    if not account_sid or not auth_token or not from_number:
        raise ValueError("Twilio credentials not configured (set TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_FROM)")
    try:
        from twilio.rest import Client as TwilioClient
    except ImportError:
        raise ValueError("twilio package not installed — run: pip install twilio")

    normalized = _normalize_phone(phone)
    logger.info("[_send_sms_otp] raw=%s normalized=%s whatsapp=%s", phone, normalized, via_whatsapp)

    client = TwilioClient(account_sid, auth_token)
    to_num = f"whatsapp:{normalized}" if via_whatsapp else normalized
    fr_num = f"whatsapp:{from_number}" if via_whatsapp else from_number
    client.messages.create(body=f"Tu código SmartLoans es: {code}. Expira en 10 min.", from_=fr_num, to=to_num)


def send_verification_code(json_file: dict):
    """Generate a 6-digit OTP, send via email / sms / whatsapp, store for 10 min."""
    try:
        target = json_file.get("target", "").strip()
        method = json_file.get("method", "email").strip().lower()  # email | sms | whatsapp
        if not target:
            return JSONResponse(content={"error": "target is required"}, status_code=400)

        code    = "".join(random.choices(string.digits, k=6))
        expires = datetime.utcnow() + timedelta(minutes=10)
        _verification_codes[target] = {"code": code, "expires": expires}
        logger.info("[send_verification_code] method=%s target=%s code=%s", method, target, code)

        if method == "email":
            _send_email_otp(target, code)
        elif method == "sms":
            _send_sms_otp(target, code, via_whatsapp=False)
        elif method == "whatsapp":
            _send_sms_otp(target, code, via_whatsapp=True)
        else:
            return JSONResponse(content={"error": f"Unknown method: {method}"}, status_code=400)

        logger.info("[send_verification_code] sent via %s to %s", method, target)
        return JSONResponse(content={"message": "Código enviado", "method": method}, status_code=200)
    except Exception as e:
        logger.exception("[send_verification_code] EXCEPTION: %s", e)
        return JSONResponse(content={"error": str(e)}, status_code=500)


def verify_code(json_file: dict):
    """Validate OTP keyed by target (email or phone). Returns { valid: bool }."""
    try:
        target = json_file.get("target", "").strip()
        code   = str(json_file.get("code", "")).strip()
        entry  = _verification_codes.get(target)
        logger.info("[verify_code] target=%s code=%s found=%s", target, code, bool(entry))

        if not entry:
            return JSONResponse(content={"valid": False, "error": "No hay código para este contacto"}, status_code=200)
        if datetime.utcnow() > entry["expires"]:
            _verification_codes.pop(target, None)
            return JSONResponse(content={"valid": False, "error": "El código expiró"}, status_code=200)
        if entry["code"] != code:
            return JSONResponse(content={"valid": False, "error": "Código incorrecto"}, status_code=200)

        _verification_codes.pop(target, None)
        logger.info("[verify_code] verified OK for %s", target)
        return JSONResponse(content={"valid": True}, status_code=200)
    except Exception as e:
        logger.exception("[verify_code] EXCEPTION: %s", e)
        return JSONResponse(content={"error": str(e)}, status_code=500)


def check_contact_sp(json_file: dict):
    """
    Look up a phone or email in dbo.clients + dbo.users.
    Returns:
      { found: true,  clientId, firstName, lastName, cellphone, email,
                      companyId, userId, userName, hasAccount }
      { found: false }
    """
    conn   = None
    cursor = None
    try:
        contact = json_file.get("contact", "").strip()
        logger.info("[check_contact_sp] contact=%s", contact)
        if not contact:
            return JSONResponse(content={"error": "contact is required"}, status_code=400)

        conn   = connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_checkContact] @pjsonfile = %s",
            (json.dumps({"checkContact": [{"contact": contact}]}),)
        )
        row = cursor.fetchone()
        logger.info("[check_contact_sp] raw row: %s", row)

        if row is None or row[0] is None:
            return JSONResponse(content={"found": False}, status_code=200)

        data = json.loads(row[0])
        if "error" in data:
            logger.error("[check_contact_sp] SP error: %s", data["error"])
            return JSONResponse(content={"error": data["error"]}, status_code=500)
        if data.get("found") is False:
            return JSONResponse(content={"found": False}, status_code=200)
        data["found"] = True
        logger.info("[check_contact_sp] RESULT: %s", data)
        return JSONResponse(content=data, status_code=200)
    except Exception as e:
        logger.exception("[check_contact_sp] EXCEPTION: %s", e)
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            if cursor: cursor.close()
        except Exception:
            pass
        try:
            if conn: conn.close()
        except Exception:
            pass


def _generate_username_candidates(base: str) -> list:
    """base itself, then numbered suffixes, then a random-suffix fallback."""
    candidates = [base]
    candidates += [f"{base}{i}" for i in range(1, 6)]
    candidates += [f"{base}{''.join(random.choices(string.digits, k=3))}" for _ in range(2)]
    logger.info("[check_username_sp] candidates=%s", candidates)
    return candidates


def check_username_sp(json_file: dict):
    """
    Checks if a desired username is available, and if not, suggests
    alternatives (numbered/random suffixes) that ARE available.
    Returns: { available: bool, suggestions: [str, ...] }
    """
    conn   = None
    cursor = None
    try:
        username = (json_file.get("username") or "").strip()
        logger.info("[check_username_sp] username=%s", username)
        if not username:
            return JSONResponse(content={"error": "username is required"}, status_code=400)

        candidates = _generate_username_candidates(username)

        conn   = connection()
        cursor = conn.cursor()
        cursor.execute(
            "EXEC [dbo].[sp_checkUsername] @pjsonfile = %s",
            (json.dumps({"checkUsername": [{"usernames": candidates}]}),)
        )
        row = cursor.fetchone()
        logger.info("[check_username_sp] raw row: %s", row)

        data = json.loads(row[0]) if row and row[0] else {}
        if "error" in data:
            logger.error("[check_username_sp] SP error: %s", data["error"])
            return JSONResponse(content={"error": data["error"]}, status_code=500)

        taken = {t["name"] for t in data.get("taken", [])}
        logger.info("[check_username_sp] taken=%s", taken)

        available = username not in taken
        suggestions = [c for c in candidates[1:] if c not in taken][:3]
        result = {"available": available, "suggestions": suggestions}
        logger.info("[check_username_sp] RESULT: %s", result)
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        logger.exception("[check_username_sp] EXCEPTION: %s", e)
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            if cursor: cursor.close()
        except Exception:
            pass
        try:
            if conn: conn.close()
        except Exception:
            pass


def all_users_sp():
    conn = None
    cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC [dbo].[sp_users_all]")

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
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass
        try:
            if conn:
                conn.close()
        except Exception:
            pass

def one_users_sp(json_file: dict):
    conn = None
    cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_users_one @pjsonfile = %s", (json.dumps(json_file),))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass
        try:
            if conn:
                conn.close()
        except Exception:
            pass


def one_users_email_sp(json_file: dict):
    conn = None
    cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_users_one_email @pjsonfile = %s", (json.dumps(json_file),))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    finally:
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass
        try:
            if conn:
                conn.close()
        except Exception:
            pass


def send_recovery_email(json_file: dict):
    conn = None
    cursor = None
    try:
        conn = connection()
        cursor = conn.cursor()
        cursor.execute("EXEC sp_users_one_email @pjsonfile = %s", (json.dumps(json_file),))
        json_result = cursor.fetchone()[0]
        user_data = json.loads(json_result)
        if not user_data.get("users") or len(user_data["users"]) == 0:
            return JSONResponse(content={"error": "User not found"}, status_code=404)
        user = user_data["users"][0]
        to_email = user["email"]
        password = user["password"]
    except Exception as e:
        return JSONResponse(content={"error": f"Database error: {str(e)}"}, status_code=500)
    finally:
        try:
            if cursor:
                cursor.close()
        except Exception:
            pass
        try:
            if conn:
                conn.close()
        except Exception:
            pass

    # Gmail SMTP settings
    smtp_server = "smtp.gmail.com"
    port = 587
    sender_email = "contreras.9999@gmail.com"
    sender_password = "kpkihuhxbzrkzpur"  # Contraseña de aplicación sin espacios

    # Email content
    subject = "Recuperación de Contraseña"
    body = f"Tu nueva contraseña es: {password}\n\nPor favor, cambia tu contraseña después de iniciar sesión."

    # Construir mensaje con UTF-8
    from email.mime.text import MIMEText
    from email.mime.multipart import MIMEMultipart

    msg = MIMEMultipart()
    msg['From'] = sender_email
    msg['To'] = to_email
    msg['Subject'] = subject
    msg.attach(MIMEText(body, 'plain', 'utf-8'))

    import ssl
    import smtplib

    context = ssl.create_default_context()

    try:
        with smtplib.SMTP(smtp_server, port) as server:
            server.starttls(context=context)
            server.login(sender_email, sender_password)
            server.sendmail(sender_email, to_email, msg.as_string())
        return JSONResponse(content={"message": "Email sent successfully"}, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

