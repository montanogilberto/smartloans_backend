import ssl, smtplib, certifi
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from fastapi.responses import JSONResponse

def send_contact_email(json_file: dict):
    try:
        contact_list = json_file.get("contact_email")
        if not isinstance(contact_list, list) or not contact_list:
            return JSONResponse(content={"error": "contact_email debe ser una lista con al menos un elemento"}, status_code=400)

        c = contact_list[0] or {}
        nombre  = (c.get("nombre") or "").strip()
        email   = (c.get("email") or "").strip()
        mensaje = (c.get("mensaje") or "").strip()

        if not nombre or not email or not mensaje:
            return JSONResponse(content={"error": "Faltan campos obligatorios: nombre, email, mensaje"}, status_code=400)

        smtp_server     = "smtp.office365.com"
        #smtp_server     = "smtp.secureserver.net"
        port            = 587
        sender_email    = "administracion@rpmtoolsmx.com"
        sender_password = "Rpmadmin#05"  # ideal: usar variable de entorno

        to_email = "administracion@rpmtoolsmx.com"
        subject = f"Nuevo mensaje de contacto - {nombre}"
        body = (
            "Has recibido un nuevo mensaje desde el formulario de contacto:\n\n"
            f"Nombre: {nombre}\n"
            f"Correo: {email}\n"
            "Mensaje:\n"
            f"{mensaje}\n"
        )

        msg = MIMEMultipart()
        msg["From"] = sender_email
        msg["To"] = to_email
        msg["Subject"] = subject
        msg.attach(MIMEText(body, "plain", "utf-8"))

        # 🔐 Contexto TLS usando el bundle de certifi
        context = ssl.create_default_context(cafile=certifi.where())

        with smtplib.SMTP(smtp_server, port) as server:
            server.ehlo()
            server.starttls(context=context)   # inicia TLS con verificación
            server.ehlo()
            server.login(sender_email, sender_password)
            server.sendmail(sender_email, [to_email], msg.as_string())

        return JSONResponse(
            content={"message": f"Formulario enviado de {sender_email} hacia {to_email}"},
            status_code=200
        )

    except Exception as e:
        return JSONResponse(content={"error": f"SMTP error: {str(e)}"}, status_code=500)
