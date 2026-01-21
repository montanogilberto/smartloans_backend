from fastapi import APIRouter, Request
from modules.mercadolibre import mercadolibre_webhook_sp

router = APIRouter(prefix="/mercadolibre", tags=["MercadoLibre"])

@router.get("/ping", summary="Ping MercadoLibre")
def ping():
    return {"status": "ok", "service": "mercadolibre"}

@router.post("/webhook", summary="MercadoLibre Webhook")
async def webhook(request: Request):
    payload = await request.json()

    # Si quieres ver en logs:
    # print("MercadoLibre webhook:", payload)

    # Guardar en DB (opcional)
    return mercadolibre_webhook_sp(payload)
