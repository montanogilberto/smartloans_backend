from fastapi import APIRouter
from fastapi.responses import JSONResponse
from modules.document_intelligence import extract_id_text_and_fields

router = APIRouter(prefix="/ocr", tags=["Document Intelligence"])


@router.post(
    "/extract-id-fields",
    summary="Extract text and MRZ-decoded fields from a captured ID document photo",
    description="""
Sends a captured ID photo (front or back, called once per side) to Azure AI
Document Intelligence for OCR, then decodes the machine-readable zone (MRZ)
if present. Domicilio and Clave de Elector are not reliably extractable from
the front of an INE (confirmed via testing — the printed fields sit on an
anti-copy watermark pattern that defeats OCR regardless of image quality)
and are returned empty for the caller to treat as manual-entry fields. CURP
is a best-effort computation (RENAPO algorithm) from the name/birthdate/sex
the MRZ does give reliably — 14 of its 18 characters, with the other 4
(state of birth, homoclave) marked "??" for manual completion.

Body: { "imageBase64": str }
Returns: { "rawText": str, "fields": { nombre, domicilio, curp, claveElector, fechaNacimiento } }
""",
)
async def extract_id_fields_route(json: dict):
    try:
        result = await extract_id_text_and_fields(json)
        return JSONResponse(result, status_code=200)
    except ValueError as e:
        return JSONResponse({"error": str(e)}, status_code=400)
    except Exception as e:
        print(f"[document_intelligence] extract_id_fields_route error: {e}")
        return JSONResponse({"error": str(e)}, status_code=500)
