"""
ObservabilityMiddleware — only requests worth investigating reach applicationLogs.

Run:  venv/bin/python -m unittest tests/test_observability_middleware.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI, HTTPException  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import observability.middleware as mw  # noqa: E402


class RequestLogLevelTest(unittest.TestCase):
    def test_fast_success_is_skipped(self):
        self.assertIsNone(mw._request_log_level(200, 150, None))
        self.assertIsNone(mw._request_log_level(304, 10, None))

    def test_client_errors_are_warn(self):
        self.assertEqual(mw._request_log_level(404, 20, None), "WARN")
        self.assertEqual(mw._request_log_level(422, 20, None), "WARN")

    def test_slow_success_is_warn(self):
        self.assertEqual(mw._request_log_level(200, mw.SLOW_REQUEST_MS, None), "WARN")
        self.assertIsNone(mw._request_log_level(200, mw.SLOW_REQUEST_MS - 1, None))

    def test_server_errors_and_exceptions_are_error(self):
        self.assertEqual(mw._request_log_level(500, 20, None), "ERROR")
        self.assertEqual(mw._request_log_level(200, 20, "Traceback ..."), "ERROR")


class MiddlewareWritesTest(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.add_middleware(mw.ObservabilityMiddleware)

        @app.get("/ok")
        def ok():
            return {"ok": True}

        @app.get("/missing")
        def missing():
            raise HTTPException(status_code=404)

        @app.get("/boom")
        def boom():
            raise RuntimeError("boom")

        self.client = TestClient(app, raise_server_exceptions=False)

    def test_success_writes_nothing(self):
        with mock.patch.object(mw, "log_application") as log:
            self.assertEqual(self.client.get("/ok").status_code, 200)
        log.assert_not_called()

    def test_404_writes_warn(self):
        with mock.patch.object(mw, "log_application") as log:
            self.client.get("/missing")
        log.assert_called_once()
        self.assertEqual(log.call_args.args[0], "WARN")
        self.assertEqual(log.call_args.kwargs["http_status"], 404)

    def test_exception_writes_error(self):
        with mock.patch.object(mw, "log_application") as log:
            self.assertEqual(self.client.get("/boom").status_code, 500)
        log.assert_called_once()
        self.assertEqual(log.call_args.args[0], "ERROR")
        self.assertIn("RuntimeError", log.call_args.kwargs["exception"])


if __name__ == "__main__":
    unittest.main()
