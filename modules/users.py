from fastapi import FastAPI
from fastapi.responses import JSONResponse
from databases import connection
import json
import smtplib
import ssl
import os

app = FastAPI()
conn = connection()

def users_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC sp_users @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def all_users_sp():

    try:
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

def one_users_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC sp_users_one @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def one_users_email_sp(json_file: dict):
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC sp_users_one_email @pjsonfile = %s", (json.dumps(json_file)))

        # Fetch the result as a JSON string
        json_result = cursor.fetchone()[0]

        # Parse the JSON string to a Python dictionary
        result = json.loads(json_result)

        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)


def send_recovery_email(json_file: dict):
    try:
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

