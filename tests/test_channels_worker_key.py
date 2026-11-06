"""
POST /whatsapp/channels decides which company owns each WhatsApp number, so
only the worker key may reach it, even to list. No database: the SP is stubbed.

Run:  venv/bin/python -m unittest tests/test_channels_worker_key.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import routes_.whatsappCloud as cloud_routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402

KEY = "test-worker-key"
BODY = {"whatsappChannels": [{"action": 1, "companyId": 2, "phoneNumberId": "111"}]}


class ChannelsWorkerKeyTest(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(cloud_routes.router)
        self.client = TestClient(app)
        self.sp = mock.Mock(return_value=JSONResponse({"result": []}))
        patches = [
            mock.patch.object(worker_key, "WORKER_KEY", KEY),
            mock.patch.object(cloud_routes, "whatsapp_channels_sp", self.sp),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def _post(self, body=BODY, **headers):
        return self.client.post("/whatsapp/channels", json=body, headers=headers).status_code

    def test_no_key_never_reaches_the_sp(self):
        self.assertEqual(self._post(), 403)
        self.sp.assert_not_called()

    def test_a_wrong_key_is_refused(self):
        self.assertEqual(self._post(**{"X-Worker-Key": "nope"}), 403)
        self.sp.assert_not_called()

    def test_listing_needs_the_key_too(self):
        self.assertEqual(self._post({"whatsappChannels": [{"companyId": 1}]}), 403)

    def test_an_unset_server_key_refuses_everyone(self):
        with mock.patch.object(worker_key, "WORKER_KEY", ""):
            self.assertEqual(self._post(**{"X-Worker-Key": ""}), 403)

    def test_the_right_key_gets_through(self):
        self.assertEqual(self._post(**{"X-Worker-Key": KEY}), 200)
        self.sp.assert_called_once()


if __name__ == "__main__":
    unittest.main()
