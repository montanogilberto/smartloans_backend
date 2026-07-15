from fastapi import APIRouter
from fastapi.responses import JSONResponse
from modules.geocoding import reverse_geocode

router = APIRouter(prefix="/api/geocode", tags=["Geocoding"])


@router.post(
    "/reverse",
    summary="Reverse-geocode GPS coordinates into a street address",
    description="""
Converts the GPS coordinates captured during presence verification into a
human-readable address, for the Domicilio field — OCR can't read Domicilio
off the ID card (see /ocr/extract-id-fields), so this is the actual address
source for that field.

Body: { "latitude": float, "longitude": float }
Returns: { "address": str }
""",
)
async def reverse_geocode_route(json: dict):
    try:
        latitude = json.get("latitude")
        longitude = json.get("longitude")
        if latitude is None or longitude is None:
            return JSONResponse({"error": "latitude and longitude are required"}, status_code=400)
        address = await reverse_geocode(float(latitude), float(longitude))
        return JSONResponse({"address": address}, status_code=200)
    except Exception as e:
        print(f"[geocoding] reverse_geocode_route error: {e}")
        return JSONResponse({"error": str(e)}, status_code=500)
