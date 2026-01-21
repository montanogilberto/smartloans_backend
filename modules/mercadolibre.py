from fastapi.responses import JSONResponse
from databases import connection
import json

conn = connection()

def mercadolibre_webhook_sp(payload: dict):
    """
    Guarda el webhook en DB (opcional). Si no tienes SP todavía,
    puedes comentar la parte de SQL y solo devolver OK.
    """
    try:
        cursor = conn.cursor()

        # Opción A (recomendado): guardar el payload completo como NVARCHAR(MAX)
        cursor.execute(
            "EXEC [dbo].[sp_mercadolibre_webhook] @pjsonfile = %s",
            (json.dumps(payload),)
        )

        result = cursor.fetchall()

        # Si tu SP regresa JSON como string en result[0][0] o [0][1], ajusta aquí.
        # Para no romper: si no regresa nada, devolvemos ok.
        if result and len(result[0]) > 0:
            return JSONResponse(content={"ok": True, "db": result[0][0]}, status_code=200)

        return JSONResponse(content={"ok": True}, status_code=200)

    except Exception as e:
        # IMPORTANTE: MercadoLibre espera 200 para no reintentar.
        # Pero para debug puedes devolver 200 con error o 500.
        # Yo recomiendo 200 + log en producción para evitar spam de reintentos.
        return JSONResponse(content={"ok": False, "error": str(e)}, status_code=200)
