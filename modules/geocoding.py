"""
Reverse geocoding — converts the GPS coordinates captured during presence
verification (see PresenceCapture.tsx) into a human-readable street address
for the Domicilio field. OCR can't read Domicilio off the ID card (confirmed
via extensive direct testing, see document_intelligence.py's module
docstring) so this is the actual address source for that field.

Uses OpenStreetMap's Nominatim — no API key or Azure-portal credential
round-trip required, so this could be verified working immediately (real
test: 19.4326,-99.1332 -> "Plaza de la Constitución, Centro, Ciudad de
México..."). Nominatim's usage policy requires a descriptive User-Agent and
caps at ~1 request/second, both trivially satisfied by this low-volume KYC
flow (one reverse-geocode call per client onboarding).
"""
import httpx

NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse"
USER_AGENT = "SmartLoansKYC/1.0 (contact: montanogilberto@gmail.com)"


async def reverse_geocode(latitude: float, longitude: float) -> str:
    params = {
        "format": "jsonv2",
        "lat": latitude,
        "lon": longitude,
        "addressdetails": 1,
        "accept-language": "es",
    }
    headers = {"User-Agent": USER_AGENT}
    async with httpx.AsyncClient(timeout=10.0) as client:
        response = await client.get(NOMINATIM_URL, params=params, headers=headers)
        response.raise_for_status()
        result = response.json()
    return result.get("display_name", "")
