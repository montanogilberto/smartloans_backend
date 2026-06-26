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

# Gmail SMTP config (same credentials used by send_recovery_email)
_SMTP_SERVER   = "smtp.gmail.com"
_SMTP_PORT     = 587
_SENDER_EMAIL  = "contreras.9999@gmail.com"
_SENDER_PWD    = "kpkihuhxbzrkzpur"

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


def send_verification_code(json_file: dict):
    """Generate a 6-digit OTP, send it to the given email, store in memory for 10 min."""
    try:
        email = json_file.get("email", "").strip().lower()
        if not email:
            return JSONResponse(content={"error": "email is required"}, status_code=400)

        code = "".join(random.choices(string.digits, k=6))
        expires = datetime.utcnow() + timedelta(minutes=10)
        _verification_codes[email] = {"code": code, "expires": expires}
        logger.info("[send_verification_code] code=%s for %s", code, email)

        # Build and send the email
        from email.mime.text import MIMEText
        from email.mime.multipart import MIMEMultipart

        msg = MIMEMultipart()
        msg["From"]    = _SENDER_EMAIL
        msg["To"]      = email
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
            server.sendmail(_SENDER_EMAIL, email, msg.as_string())

        logger.info("[send_verification_code] email sent to %s", email)
        return JSONResponse(content={"message": "Código enviado", "email": email}, status_code=200)
    except Exception as e:
        logger.exception("[send_verification_code] EXCEPTION: %s", e)
        return JSONResponse(content={"error": str(e)}, status_code=500)


def verify_code(json_file: dict):
    """Validate OTP. Returns { valid: true } or { valid: false, error: '...' }."""
    try:
        email = json_file.get("email", "").strip().lower()
        code  = str(json_file.get("code", "")).strip()
        entry = _verification_codes.get(email)

        if not entry:
            return JSONResponse(content={"valid": False, "error": "No hay código para este email"}, status_code=200)
        if datetime.utcnow() > entry["expires"]:
            _verification_codes.pop(email, None)
            return JSONResponse(content={"valid": False, "error": "El código expiró"}, status_code=200)
        if entry["code"] != code:
            return JSONResponse(content={"valid": False, "error": "Código incorrecto"}, status_code=200)

        _verification_codes.pop(email, None)
        logger.info("[verify_code] verified OK for %s", email)
        return JSONResponse(content={"valid": True}, status_code=200)
    except Exception as e:
        logger.exception("[verify_code] EXCEPTION: %s", e)
        return JSONResponse(content={"error": str(e)}, status_code=500)


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

