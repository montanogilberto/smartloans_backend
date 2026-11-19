"""Profile avatar: the client's front selfie, retouched, on a black studio background.

The avatar is a DERIVED copy for display only (app header, POS). It is written
next to — never over — the KYC captures: `selfies/selfie_front.jpg` is biometric
evidence compared against the INE, so it must stay exactly as captured.

    source : {clientId}/selfies/selfie_front.jpg   (sharp liveness frame)
    output : {clientId}/profile/avatar.jpg          (square, <= 1024 px)

Everything runs on OpenCV, already a dependency:
- Person segmentation: MediaPipe "selfie_segmenter" (Apache-2.0, 250 KB) loaded
  with cv2.dnn.readNetFromTFLite — no TensorFlow/MediaPipe install needed.
- Edges: a narrow smooth band, recoloured from the person so the old wall
  doesn't glow around the shoulders on black.
- Retouch: skin-only smoothing, gentle local contrast, detail kept on eyes/hair.

`build_avatar` is pure (bytes in, bytes out) so it is testable without Azure.
"""
import os
import threading

import cv2
import numpy as np

MODEL_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                          "files", "ml", "selfie_segmenter.tflite")

AVATAR_SOURCE_SIDE = "selfie_front"
BLOB_FOLDER_PROFILE = "profile"
AVATAR_FILENAME = "avatar.jpg"
AVATAR_MAX_SIDE = 1024
_MODEL_INPUT = 256
# Below this share of the frame the capture has no usable person in it.
_MIN_PERSON_SHARE = 0.03

_net = None
_net_lock = threading.Lock()  # cv2.dnn.Net is not safe to share across threads


class NoPersonFound(ValueError):
    pass


def _forward(rgb_small: np.ndarray) -> np.ndarray:
    global _net
    blob = cv2.dnn.blobFromImage(rgb_small, 1 / 255.0, (_MODEL_INPUT, _MODEL_INPUT))
    with _net_lock:
        if _net is None:
            _net = cv2.dnn.readNetFromTFLite(MODEL_PATH)
        _net.setInput(blob)
        out = _net.forward()
    return np.squeeze(out).astype(np.float32)


def _largest_region(mask: np.ndarray) -> np.ndarray:
    """Keep only the biggest blob, so a stray chair or coat never survives."""
    binary = (mask > 0.5).astype(np.uint8)
    n, labels, stats, _ = cv2.connectedComponentsWithStats(binary)
    if n <= 1:
        return mask
    keep = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    region = cv2.dilate((labels == keep).astype(np.uint8), np.ones((15, 15), np.uint8))
    return mask * region


def person_mask(bgr: np.ndarray) -> np.ndarray:
    """Float mask in [0, 1], same size as the image."""
    h, w = bgr.shape[:2]
    small = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    mask = cv2.resize(_forward(small), (w, h), interpolation=cv2.INTER_LINEAR)
    mask = _largest_region(np.clip(mask, 0, 1))
    if float((mask > 0.5).mean()) < _MIN_PERSON_SHARE:
        raise NoPersonFound("no person in the selfie")
    # Narrow, smooth edge band: wide soft edges carry a ring of the old wall.
    t = np.clip((mask - 0.35) / 0.3, 0, 1)
    alpha = t * t * (3 - 2 * t)
    return cv2.GaussianBlur(alpha, (0, 0), max(1.0, min(h, w) / 700))


def _decontaminate(img: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Edge pixels are a mix of person + old wall. Recolour them from nearby
    solid-person pixels so the bright wall doesn't glow on black."""
    solid = cv2.erode((alpha > 0.98).astype(np.float32), np.ones((3, 3), np.uint8))
    sigma = max(2.0, min(img.shape[:2]) / 240)
    weight = cv2.GaussianBlur(solid, (0, 0), sigma)
    inside = cv2.GaussianBlur(img * solid[..., None], (0, 0), sigma) / np.maximum(weight, 1e-4)[..., None]
    # Only the thin semi-transparent band; solid pixels keep their own detail.
    edge = ((1 - alpha) * (alpha > 0.01) * (weight > 0.02))[..., None]
    return img * (1 - edge) + inside * edge


def _skin_mask(bgr: np.ndarray, person: np.ndarray) -> np.ndarray:
    ycrcb = cv2.cvtColor(bgr, cv2.COLOR_BGR2YCrCb)
    skin = cv2.inRange(ycrcb, (0, 133, 77), (255, 173, 127)).astype(np.float32) / 255.0
    skin = cv2.GaussianBlur(skin * person, (0, 0), 3)
    return np.clip(skin, 0, 1)


def retouch(bgr: np.ndarray, person: np.ndarray) -> np.ndarray:
    """Studio-style retouch of the subject; background handled by the caller."""
    img = bgr.astype(np.float32)
    short = min(bgr.shape[:2])
    skin = _skin_mask(bgr, person)[..., None]

    # 1. Skin smoothing — edge-preserving, only where there is skin.
    smooth = cv2.bilateralFilter(bgr, 0, 28, max(3, short / 140)).astype(np.float32)
    img = img * (1 - 0.55 * skin) + smooth * (0.55 * skin)

    # 2. Gentle local contrast on lightness (half-strength CLAHE).
    lab = cv2.cvtColor(np.clip(img, 0, 255).astype(np.uint8), cv2.COLOR_BGR2LAB)
    l_chan = lab[..., 0]
    lifted = cv2.createCLAHE(clipLimit=1.6, tileGridSize=(8, 8)).apply(l_chan)
    lab[..., 0] = cv2.addWeighted(l_chan, 0.65, lifted, 0.35, 0)
    img = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR).astype(np.float32)

    # 3. A touch more colour and brightness.
    hsv = cv2.cvtColor(np.clip(img, 0, 255).astype(np.uint8), cv2.COLOR_BGR2HSV).astype(np.float32)
    hsv[..., 1] *= 1.06
    hsv[..., 2] = hsv[..., 2] * 1.03 + 2
    img = cv2.cvtColor(np.clip(hsv, 0, 255).astype(np.uint8), cv2.COLOR_HSV2BGR).astype(np.float32)

    # 4. Crisp eyes/hair/clothing, but don't bring skin texture back.
    blur = cv2.GaussianBlur(img, (0, 0), max(1.0, short / 600))
    sharpen = 0.25 * (1 - 0.9 * skin)
    img = img + (img - blur) * sharpen
    return np.clip(img, 0, 255)


def _studio_background(h: int, w: int, head_x: float, head_y: float) -> np.ndarray:
    """Black with a faint glow behind the head, so the subject separates from it."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.sqrt(((xx - head_x) / (0.75 * w)) ** 2 + ((yy - head_y) / (0.75 * w)) ** 2)
    glow = (np.clip(1 - r, 0, 1) ** 2) * 26
    return np.repeat(glow[..., None], 3, axis=2)


def _square_crop_box(person: np.ndarray) -> tuple:
    h, w = person.shape
    rows = np.where((person > 0.5).any(axis=1))[0]
    head_top = int(rows[0]) if len(rows) else 0
    band = person[head_top:head_top + max(1, h // 5)] > 0.5
    cols = np.where(band.any(axis=0))[0]
    head_x = int((cols[0] + cols[-1]) / 2) if len(cols) else w // 2
    side = min(h, w)
    top = int(np.clip(head_top - 0.12 * side, 0, h - side))
    left = int(np.clip(head_x - side / 2, 0, w - side))
    return left, top, side, head_x, head_top


def build_avatar(image_bytes: bytes) -> bytes:
    """Selfie JPEG/PNG bytes -> retouched square avatar JPEG bytes.

    Raises NoPersonFound when there is no usable person, ValueError when the
    bytes are not an image.
    """
    bgr = cv2.imdecode(np.frombuffer(image_bytes, np.uint8), cv2.IMREAD_COLOR)
    if bgr is None:
        raise ValueError("selfie is not a readable image")

    person = person_mask(bgr)
    subject = _decontaminate(retouch(bgr, person), person)
    h, w = bgr.shape[:2]
    left, top, side, head_x, head_top = _square_crop_box(person)
    background = _studio_background(h, w, head_x, head_top + 0.25 * side)

    alpha = person[..., None]
    composite = subject * alpha + background * (1 - alpha)
    square = np.clip(composite[top:top + side, left:left + side], 0, 255).astype(np.uint8)
    if side > AVATAR_MAX_SIDE:
        square = cv2.resize(square, (AVATAR_MAX_SIDE, AVATAR_MAX_SIDE), interpolation=cv2.INTER_AREA)

    ok, encoded = cv2.imencode(".jpg", square, [cv2.IMWRITE_JPEG_QUALITY, 90,
                                                cv2.IMWRITE_JPEG_OPTIMIZE, 1])
    if not ok:
        raise ValueError("could not encode avatar")
    return encoded.tobytes()
