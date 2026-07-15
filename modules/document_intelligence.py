"""
Azure AI Document Intelligence — ID document text/MRZ extraction.

Replaces client-side Tesseract.js OCR (previously self-hosted in the
frontend's idOcr.ts) for reading INE (Mexican voter ID) captures. Confirmed
via direct testing against real captures this session: Tesseract's general
"spa" model was never trained on ID-card layouts or the OCR-B MRZ font and
produced unusable text regardless of image sharpness/resolution/DPI tuning.

Also confirmed via the same direct testing — using both Azure's
prebuilt-idDocument AND prebuilt-read models, at both ~300 DPI and full
sensor resolution — that the FRONT of the card consistently fails to OCR
beyond the large header text, on every engine/resolution combination tried.
This looks like a deliberate document security feature: the printed fields
sit on an anti-copy watermark pattern that both OCR engines treat as
background noise, while the back's MRZ (designed to be machine-readable per
ICAO 9303) reads cleanly. So: Domicilio, CURP, and Clave de Elector are NOT
reliably extractable by this or any general OCR approach and stay
manual-entry fields in the UI. This module focuses on what MRZ decoding can
actually deliver — name, birthdate, sex — plus a best-effort regex pass over
whatever raw text comes back, in case a future/different capture manages to
read more of the front.
"""
import os
import re
import asyncio
import httpx

AZURE_DOC_INTEL_ENDPOINT = os.getenv("AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT", "").rstrip("/")
AZURE_DOC_INTEL_KEY = os.getenv("AZURE_DOCUMENT_INTELLIGENCE_KEY", "")

# formrecognizer path + 2023-07-31 confirmed working directly against this
# resource — the newer documentintelligence/... path 404s on it.
API_VERSION = "2023-07-31"
MODEL_ID = "prebuilt-read"  # general OCR. prebuilt-idDocument was also
                             # tested and added no value for INE: it never
                             # populated structured fields, and sometimes
                             # misclassified the front as the wrong document
                             # type (idDocument.residencePermit), extracting
                             # even less than prebuilt-read did.

POLL_INTERVAL_SECONDS = 1.0
MAX_POLL_ATTEMPTS = 30  # ~30s cap so a stuck request can't hang the worker

CURP_REGEX = re.compile(r"[A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z0-9]\d")
CLAVE_ELECTOR_REGEX = re.compile(r"[A-Z]{6}\d{9,12}")

# ── Best-effort CURP computation ─────────────────────────────────────────────
# Confirmed via direct testing against real captures (both front and back,
# fresh OCR calls) that CURP as printed is never readable — same watermark
# issue as Domicilio/Clave de Elector. But 14 of its 18 characters are
# mechanically derivable from data the MRZ DOES give us reliably (name,
# birthdate, sex) per the public RENAPO algorithm ("Instructivo Normativo
# para la Asignación de la CURP"). The other 4 — state of birth (positions
# 12-13) and the homoclave/check digit (17-18) — need data this pipeline
# doesn't have (state of birth isn't in the MRZ; homoclave requires a RENAPO
# database lookup) and are left as "??" placeholders. Like every other
# extracted field, this is shown as an editable suggestion, never persisted
# as authoritative — an imperfect match against RENAPO's actual inconvenient-
# word substitution table (rare, and only affects the first 4 characters)
# just means staff correct it by hand same as any other OCR field.
CURP_VOWELS = set("AEIOU")

CURP_INCONVENIENT_WORDS = {
    "BUEI", "BUEY", "CACA", "CACO", "CAGA", "CAGO", "CAKA", "CAKO", "COGE", "COJA",
    "COJE", "COJI", "COJO", "CULO", "FETO", "GUEY", "JOTO", "KACA", "KACO", "KAGA",
    "KAGO", "KAKA", "KAKO", "KOGE", "KOJO", "KULO", "MAME", "MAMO", "MEAR", "MEAS",
    "MEON", "MION", "MOCO", "MOKO", "MULA", "MULO", "NACA", "NACO", "PEDA", "PEDO",
    "PENE", "PIPI", "PITO", "POPO", "PUTA", "PUTO", "QULO", "RATA", "RUIN", "SENO",
    "TETA", "VACA", "VAGA", "VAGO", "VAKA", "VUEI", "VUEY", "WUEY", "WEY",
}


def _first_internal_vowel(word: str) -> str:
    for ch in word[1:]:
        if ch in CURP_VOWELS:
            return ch
    return "X"


def _first_internal_consonant(word: str) -> str:
    for ch in word[1:]:
        if ch.isalpha() and ch not in CURP_VOWELS:
            return ch
    return "X"


def compute_curp_best_effort(
    apellido_paterno: str, apellido_materno: str, nombre_propio: str,
    yy: str, mm: str, dd: str, sexo: str
) -> str:
    if not apellido_paterno or not nombre_propio or not sexo or sexo not in ("H", "M"):
        return ""

    p1 = apellido_paterno[0]
    p2 = _first_internal_vowel(apellido_paterno)
    p3 = apellido_materno[0] if apellido_materno else "X"
    p4 = nombre_propio[0]

    prefix = p1 + p2 + p3 + p4
    if prefix in CURP_INCONVENIENT_WORDS:
        p2 = "X"

    p14 = _first_internal_consonant(apellido_paterno)
    p15 = _first_internal_consonant(apellido_materno) if apellido_materno else "X"
    p16 = _first_internal_consonant(nombre_propio)

    return f"{p1}{p2}{p3}{p4}{yy}{mm}{dd}{sexo}??{p14}{p15}{p16}??"


def _strip_data_url_prefix(image_base64: str) -> str:
    if image_base64.startswith("data:"):
        return image_base64.split(",", 1)[1]
    return image_base64


async def _analyze_document(image_base64: str) -> dict:
    if not AZURE_DOC_INTEL_ENDPOINT or not AZURE_DOC_INTEL_KEY:
        raise RuntimeError("Azure Document Intelligence is not configured (missing endpoint/key).")

    base64_data = _strip_data_url_prefix(image_base64)
    analyze_url = f"{AZURE_DOC_INTEL_ENDPOINT}/formrecognizer/documentModels/{MODEL_ID}:analyze?api-version={API_VERSION}"
    headers = {
        "Ocp-Apim-Subscription-Key": AZURE_DOC_INTEL_KEY,
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        submit_response = await client.post(analyze_url, headers=headers, json={"base64Source": base64_data})
        if submit_response.status_code != 202:
            raise RuntimeError(f"Document Intelligence submit failed: {submit_response.status_code} {submit_response.text}")

        operation_location = submit_response.headers.get("Operation-Location")
        if not operation_location:
            raise RuntimeError("Document Intelligence response missing Operation-Location header.")

        for _ in range(MAX_POLL_ATTEMPTS):
            await asyncio.sleep(POLL_INTERVAL_SECONDS)
            poll_response = await client.get(operation_location, headers={"Ocp-Apim-Subscription-Key": AZURE_DOC_INTEL_KEY})
            poll_response.raise_for_status()
            result = poll_response.json()
            status = result.get("status")
            if status == "succeeded":
                return result.get("analyzeResult", {})
            if status == "failed":
                raise RuntimeError(f"Document Intelligence analysis failed: {result}")

        raise RuntimeError("Document Intelligence analysis timed out.")


# ── MRZ decoding ──────────────────────────────────────────────────────────

def _mrz_char_pool(raw_text: str) -> str:
    """Concatenate all MRZ-looking segments from raw OCR text into one
    character pool. Azure sometimes returns the 3 physical MRZ lines as
    separate text lines and sometimes merges them into a single line
    (confirmed both behaviors on the same resource/model against real
    captures) — searching a pooled blob with regex instead of assuming a
    fixed line count works regardless of which one it picks."""
    parts = []
    for line in raw_text.split("\n"):
        compact = line.replace(" ", "").upper()
        if len(compact) < 15:
            continue
        alnum_count = sum(1 for c in compact if c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789<")
        if alnum_count / len(compact) > 0.85:
            parts.append(compact)
    return "".join(parts)


def parse_mrz(raw_text: str) -> dict:
    """Best-effort TD1 (3-line, 30-char) MRZ decode. Returns whatever it
    can confidently find — empty strings for anything not found. Not
    guaranteed correct on every OCR error; the caller shows these as
    editable fields, never authoritative data.

    The MRZ sex position follows the ICAO 9303 standard ('M'/'F'), NOT the
    Spanish Hombre/Mujer letters printed on the card's front — confirmed
    against a real capture where a male cardholder's MRZ read literal 'M'
    (ICAO Male), not 'H'. Mapped to CURP's H/M convention below."""
    pool = _mrz_char_pool(raw_text)
    # The underscore-prefixed keys are internal-only (used for CURP
    # best-effort computation below), not part of the public fields shape
    # returned to the frontend.
    result = {
        "nombre": "", "fechaNacimiento": "",
        "_apellidoPaterno": "", "_apellidoMaterno": "", "_nombrePropio": "",
        "_yy": "", "_mm": "", "_dd": "", "_sexo": "",
    }
    if len(pool) < 20:
        return result

    # Name: "<<"-separated surname/given-name block of letters and single
    # '<' filler chars. Each group uses "<(?!<)" (a '<' NOT followed by
    # another '<') rather than a plain "<{2,}" character class — greedy
    # [A-Z<]{2,} would otherwise swallow the "<<" separator itself, since
    # '<' is part of its own class (confirmed: it grabbed straight through
    # to a trailing "<<<<<" padding run and left the second group empty).
    # search() finds the first match, which correctly skips past any "<<"
    # inside the digit-heavy document-number/optional-data zones, since
    # those neighborhoods fail the letters-and-< requirement.
    name_match = re.search(r"((?:[A-Z]|<(?!<))+)<<((?:[A-Z]|<(?!<))+)", pool)
    if name_match:
        surname_raw = name_match.group(1)
        given_raw = name_match.group(2)
        surname = surname_raw.replace("<", " ").strip()
        given = given_raw.replace("<", " ").strip()
        if surname or given:
            result["nombre"] = f"{surname} {given}".strip()

        # A single '<' (not "<<") inside the surname block separates
        # apellido paterno from materno, same convention as the "<<" that
        # separates the whole surname block from the given-name block.
        surname_parts = [p for p in surname_raw.split("<") if p]
        given_parts = [p for p in given_raw.split("<") if p]
        result["_apellidoPaterno"] = surname_parts[0] if surname_parts else ""
        result["_apellidoMaterno"] = surname_parts[1] if len(surname_parts) > 1 else ""
        propio = given_parts[0] if given_parts else ""
        # RENAPO rule: when the first given name is a common compound
        # prefix (María/José, or their abbreviations), CURP position 4
        # uses the SECOND given name instead — e.g. "MARIA GUADALUPE" uses
        # G, not M.
        if len(given_parts) > 1 and given_parts[0] in ("MARIA", "JOSE", "MA", "J"):
            propio = given_parts[1]
        result["_nombrePropio"] = propio

    # Birthdate + sex: TD1 line 2 is 6-digit YYMMDD + 1 check digit + M/F
    # (ICAO standard), found anywhere in the pool regardless of which
    # physical line it ended up on after OCR. Also tolerates a literal 'H'
    # in case some capture ever surfaces the Spanish letter instead.
    date_match = re.search(r"(\d{6})\d([MFH])", pool)
    if date_match:
        yy, mm, dd = date_match.group(1)[0:2], date_match.group(1)[2:4], date_match.group(1)[4:6]
        icao_sex = date_match.group(2)
        try:
            if 1 <= int(mm) <= 12 and 1 <= int(dd) <= 31:
                century = "19" if int(yy) > 30 else "20"
                result["fechaNacimiento"] = f"{dd}/{mm}/{century}{yy}"
                result["_yy"], result["_mm"], result["_dd"] = yy, mm, dd
                # Map to CURP's H(ombre)/M(ujer) convention: ICAO 'M' means
                # Male → CURP 'H'; ICAO 'F' means Female → CURP 'M'.
                if icao_sex == "M" or icao_sex == "H":
                    result["_sexo"] = "H"
                elif icao_sex == "F":
                    result["_sexo"] = "M"
        except ValueError:
            pass

    return result


def _regex_fallback(raw_text: str) -> dict:
    """Cheap bonus pass in case any capture manages to surface a directly-
    printed CURP/Clave de Elector — costs nothing to try, not expected to
    fire reliably given the front-of-card OCR limitation documented above."""
    upper_text = raw_text.upper()
    curp_match = CURP_REGEX.search(upper_text)
    clave_match = CLAVE_ELECTOR_REGEX.search(upper_text)
    return {
        "curp": curp_match.group(0) if curp_match else "",
        "claveElector": clave_match.group(0) if clave_match else "",
    }


async def extract_id_text_and_fields(payload: dict) -> dict:
    """
    Body: { "imageBase64": str }
    Returns: { "rawText": str, "fields": { nombre, domicilio, curp, claveElector, fechaNacimiento } }
    """
    image_base64 = payload.get("imageBase64")
    if not image_base64:
        raise ValueError("imageBase64 is required")

    analyze_result = await _analyze_document(image_base64)
    raw_text = analyze_result.get("content", "")

    mrz_fields = parse_mrz(raw_text)
    regex_fields = _regex_fallback(raw_text)

    curp = regex_fields["curp"] or compute_curp_best_effort(
        mrz_fields["_apellidoPaterno"], mrz_fields["_apellidoMaterno"], mrz_fields["_nombrePropio"],
        mrz_fields["_yy"], mrz_fields["_mm"], mrz_fields["_dd"], mrz_fields["_sexo"],
    )

    fields = {
        "nombre": mrz_fields["nombre"],
        "domicilio": "",
        "curp": curp,
        "claveElector": regex_fields["claveElector"],
        "fechaNacimiento": mrz_fields["fechaNacimiento"],
    }

    return {"rawText": raw_text, "fields": fields}
