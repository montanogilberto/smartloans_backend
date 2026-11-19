"""Profile avatar: derived from selfie_front, written to {clientId}/profile/avatar.jpg,
never over the KYC capture, and never able to fail the KYC upload.
Synthetic images only — this repo is public, no real selfies in tests."""
import asyncio
import base64
import json
import unittest
from unittest import mock

import cv2
import numpy as np

from modules import clientFaceRecognitions as cfr
from modules import profileAvatar as pa


def _jpeg(img: np.ndarray) -> bytes:
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


def _portrait(h=1280, w=720) -> np.ndarray:
    """Bright blue 'wall' with a skin-tone head and a green shirt."""
    img = np.full((h, w, 3), (200, 120, 40), np.uint8)
    cv2.ellipse(img, (w // 2, int(h * 0.35)), (w // 4, int(h * 0.16)), 0, 0, 360, (120, 150, 200), -1)
    cv2.rectangle(img, (0, int(h * 0.55)), (w, h), (170, 220, 170), -1)
    return img


def _fake_mask(img_small):
    """Stand-in for the model: a head + shoulders blob on a 256x256 grid."""
    m = np.zeros((256, 256), np.float32)
    cv2.ellipse(m, (128, 90), (64, 41), 0, 0, 360, 1.0, -1)
    m[140:, :] = 1.0
    return m


class BuildAvatarTests(unittest.TestCase):
    def test_square_jpeg_with_black_background(self):
        with mock.patch.object(pa, "_forward", side_effect=_fake_mask):
            out = pa.build_avatar(_jpeg(_portrait()))
        avatar = cv2.imdecode(np.frombuffer(out, np.uint8), cv2.IMREAD_COLOR)
        h, w = avatar.shape[:2]
        self.assertEqual(h, w)
        self.assertLessEqual(w, pa.AVATAR_MAX_SIDE)
        # Top corners were blue wall — now (near) black.
        self.assertLess(int(avatar[5, 5].max()), 30)
        self.assertLess(int(avatar[5, w - 6].max()), 30)

    def test_large_selfie_is_scaled_to_max_side(self):
        with mock.patch.object(pa, "_forward", side_effect=_fake_mask):
            out = pa.build_avatar(_jpeg(_portrait(2400, 1600)))
        avatar = cv2.imdecode(np.frombuffer(out, np.uint8), cv2.IMREAD_COLOR)
        self.assertEqual(avatar.shape[:2], (pa.AVATAR_MAX_SIDE, pa.AVATAR_MAX_SIDE))

    def test_no_person_raises(self):
        with mock.patch.object(pa, "_forward", return_value=np.zeros((256, 256), np.float32)):
            with self.assertRaises(pa.NoPersonFound):
                pa.build_avatar(_jpeg(_portrait()))

    def test_not_an_image_raises(self):
        with self.assertRaises(ValueError):
            pa.build_avatar(b"not an image")

    def test_bundled_model_loads_and_runs(self):
        mask = pa._forward(cv2.cvtColor(_portrait(), cv2.COLOR_BGR2RGB))
        self.assertEqual(mask.shape, (256, 256))
        self.assertGreaterEqual(float(mask.min()), 0.0)
        self.assertLessEqual(float(mask.max()), 1.0)


class UploadHookTests(unittest.TestCase):
    RAW = b"\xff\xd8selfie-bytes"

    def upload(self, side):
        payload = {"companyId": 1008, "clientId": 3371, "side": side,
                   "imageBase64": "data:image/jpeg;base64," + base64.b64encode(self.RAW).decode()}
        with mock.patch.object(cfr, "_upload_to_blob", return_value="https://x/blob") as up, \
                mock.patch.object(cfr, "save_profile_avatar_in_background") as bg:
            res = asyncio.run(cfr.upload_id_image_connector(payload))
        return res, up, bg

    def test_front_selfie_is_stored_untouched_and_queues_avatar(self):
        res, up, bg = self.upload("selfie_front")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(json.loads(res.body)["blobUrl"], "https://x/blob")
        raw, path = up.call_args.args[:2]
        self.assertEqual(raw, self.RAW)                      # KYC capture as sent
        self.assertEqual(path, "3371/selfies/selfie_front.jpg")
        bg.assert_called_once_with(1008, 3371, self.RAW)

    def test_other_sides_do_not_build_an_avatar(self):
        for side in ("selfie", "front", "back", "selfie_left"):
            _, _, bg = self.upload(side)
            bg.assert_not_called()

    def test_avatar_goes_to_profile_folder_never_over_selfie(self):
        with mock.patch.object(cfr, "build_avatar", return_value=b"avatar"), \
                mock.patch.object(cfr, "_upload_to_blob", return_value="u") as up:
            cfr.save_profile_avatar(1008, 3371, self.RAW)
        raw, path = up.call_args.args[:2]
        self.assertEqual((raw, path), (b"avatar", "3371/profile/avatar.jpg"))
        self.assertEqual(up.call_args.kwargs["cache_control"], "no-cache")

    def test_background_failure_is_swallowed(self):
        with mock.patch.object(cfr, "save_profile_avatar", side_effect=RuntimeError("boom")), \
                mock.patch.object(cfr.threading, "Thread") as thread:
            cfr.save_profile_avatar_in_background(1008, 3371, self.RAW)
            run = thread.call_args.kwargs["target"]
            run()  # must not raise


if __name__ == "__main__":
    unittest.main()
