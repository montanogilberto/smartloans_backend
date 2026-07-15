"""
Automated signature comparison — printed ID signature vs. a signature
captured at contract-signing time (SignaturePad canvas).

This compares two fundamentally different capture modalities: a small,
possibly print-degraded photograph of ink-on-card vs. a clean vector-like
canvas drawing. There's no labeled genuine/forged dataset to calibrate
against and no trained signature-verification model available here, so
this uses a classical-CV pipeline (OpenCV) rather than a black-box "AI"
claim — the score is advisory/audit data for staff review, not a hard
gate on onboarding (see the calling code in clientFaceRecognitions.py).

Pipeline: binarize both images (Otsu threshold, ink vs. background) ->
crop each to its own ink bounding box -> resize both to a shared canonical
size -> combine three scores:
  - shape (Hu-moment contour comparison, cv2.matchShapes) — tolerant of
    translation/scale/rotation, appropriate given the two captures come
    from completely different sources
  - overlap (IoU of the two centered/scaled binary ink masks) — catches
    fine stroke-shape agreement Hu moments can miss
  - density ratio — sanity check against a near-blank or noise-only crop
    scoring a false match
"""
import cv2
import numpy as np

CANONICAL_SIZE = (300, 150)  # (width, height)
MIN_INK_PIXELS = 40  # below this, treat the crop as "no signature found"


def _decode_to_gray(image_bytes: bytes) -> np.ndarray:
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise ValueError("Could not decode image bytes")
    return img


def _binarize(gray: np.ndarray, denoise: bool) -> np.ndarray:
    """Otsu-threshold to a binary mask where ink = 255, background = 0.
    `denoise` applies a light blur + morphological open/close pass, meant
    for the photographed ID crop (JPEG/print artifacts) — the clean
    SignaturePad output doesn't need it."""
    work = gray
    if denoise:
        work = cv2.GaussianBlur(work, (3, 3), 0)
    _, mask = cv2.threshold(work, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    if denoise:
        kernel = np.ones((2, 2), np.uint8)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)
        mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    return mask


def _crop_to_ink(mask: np.ndarray) -> np.ndarray | None:
    """Crop to the bounding box of non-zero (ink) pixels. Returns None if
    there's essentially nothing there (blank/near-blank crop)."""
    ink_pixels = cv2.findNonZero(mask)
    if ink_pixels is None or len(ink_pixels) < MIN_INK_PIXELS:
        return None
    x, y, w, h = cv2.boundingRect(ink_pixels)
    return mask[y:y + h, x:x + w]


def _resize_canonical(mask: np.ndarray) -> np.ndarray:
    """Aspect-preserving resize into CANONICAL_SIZE, letterboxed (padded
    with background) rather than stretched, so stroke proportions stay
    comparable between the two very different source resolutions."""
    target_w, target_h = CANONICAL_SIZE
    h, w = mask.shape
    scale = min(target_w / w, target_h / h)
    new_w, new_h = max(1, int(w * scale)), max(1, int(h * scale))
    resized = cv2.resize(mask, (new_w, new_h), interpolation=cv2.INTER_AREA)

    canvas = np.zeros((target_h, target_w), dtype=np.uint8)
    x_off = (target_w - new_w) // 2
    y_off = (target_h - new_h) // 2
    canvas[y_off:y_off + new_h, x_off:x_off + new_w] = resized
    return canvas


def _largest_contour(mask: np.ndarray):
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    return max(contours, key=cv2.contourArea)


def _shape_score(mask_a: np.ndarray, mask_b: np.ndarray) -> float:
    contour_a, contour_b = _largest_contour(mask_a), _largest_contour(mask_b)
    if contour_a is None or contour_b is None:
        return 0.0
    hu_distance = cv2.matchShapes(contour_a, contour_b, cv2.CONTOURS_MATCH_I1, 0.0)
    # matchShapes returns 0 for identical shapes, unbounded above for very
    # different ones — map to 0-100 without needing a hard clamp.
    return 100.0 / (1.0 + hu_distance)


def _overlap_score(mask_a: np.ndarray, mask_b: np.ndarray) -> float:
    a_bool = mask_a > 0
    b_bool = mask_b > 0
    union = np.logical_or(a_bool, b_bool).sum()
    if union == 0:
        return 0.0
    intersection = np.logical_and(a_bool, b_bool).sum()
    return 100.0 * intersection / union


def _density_ratio_score(mask_a: np.ndarray, mask_b: np.ndarray) -> float:
    density_a = np.count_nonzero(mask_a) / mask_a.size
    density_b = np.count_nonzero(mask_b) / mask_b.size
    if max(density_a, density_b) == 0:
        return 0.0
    return 100.0 * min(density_a, density_b) / max(density_a, density_b)


def compare_signatures(
    image_bytes_a: bytes,
    image_bytes_b: bytes,
    threshold: float = 55.0,
) -> dict:
    """
    Returns:
      {
        matchScore: float | None,   # 0-100, None if either crop had no
                                     # detectable ink (see 'reason')
        matchPassed: bool | None,
        shapeScore: float | None,
        overlapScore: float | None,
        densityRatioScore: float | None,
        reason: str,                 # "ok" | "no_ink_a" | "no_ink_b" | "no_ink_both"
      }
    """
    gray_a = _decode_to_gray(image_bytes_a)
    gray_b = _decode_to_gray(image_bytes_b)

    mask_a = _crop_to_ink(_binarize(gray_a, denoise=True))
    mask_b = _crop_to_ink(_binarize(gray_b, denoise=True))

    if mask_a is None and mask_b is None:
        reason = "no_ink_both"
    elif mask_a is None:
        reason = "no_ink_a"
    elif mask_b is None:
        reason = "no_ink_b"
    else:
        reason = "ok"

    if reason != "ok":
        return {
            "matchScore": None, "matchPassed": None,
            "shapeScore": None, "overlapScore": None, "densityRatioScore": None,
            "reason": reason,
        }

    canonical_a = _resize_canonical(mask_a)
    canonical_b = _resize_canonical(mask_b)

    shape_score = _shape_score(canonical_a, canonical_b)
    overlap_score = _overlap_score(canonical_a, canonical_b)
    density_score = _density_ratio_score(canonical_a, canonical_b)

    combined = 0.5 * shape_score + 0.4 * overlap_score + 0.1 * density_score

    # Cast numpy scalar types (np.float64/np.bool_ from the OpenCV/numpy
    # calls above) to native Python types — numpy scalars aren't JSON-
    # serializable and would break FastAPI's JSONResponse downstream.
    return {
        "matchScore": round(float(combined), 2),
        "matchPassed": bool(combined >= threshold),
        "shapeScore": round(float(shape_score), 2),
        "overlapScore": round(float(overlap_score), 2),
        "densityRatioScore": round(float(density_score), 2),
        "reason": "ok",
    }
