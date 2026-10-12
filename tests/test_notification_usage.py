"""
Provider usage for the Notifications screen — pure payload building + route/fallback.

Run:  venv/bin/python -m unittest tests/test_notification_usage.py -v
"""
import os
import sys
import unittest
from types import SimpleNamespace as R
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.notificationUsage as nu  # noqa: E402
import routes_.notificationUsage as routes  # noqa: E402


def rec(category, count, price="0", unit="usd"):
    return R(category=category, count=count, price=price, price_unit=unit)


class BuildUsageTest(unittest.TestCase):
    def setUp(self):
        os.environ.pop("WHATSAPP_FREE_MONTHLY_LIMIT", None)

    def test_maps_whatsapp_and_sms_categories(self):
        usage = nu.build_usage([
            rec("channels-whatsapp-outbound", "842"), rec("channels-whatsapp-inbound", "30"),
            rec("channels-whatsapp", "100", "1.5"), rec("channels-whatsapp-conversation-free", "60"),
            rec("sms-outbound", "4"), rec("totalprice", None, "9"),
        ])
        self.assertEqual(usage["whatsapp"]["outboundMessages"], 842)
        self.assertEqual(usage["whatsapp"]["billableConversations"], 40)
        self.assertEqual(usage["whatsapp"]["price"], 1.5)
        self.assertEqual(usage["sms"]["outboundMessages"], 4)

    def test_no_limit_configured_reports_no_remaining(self):
        usage = nu.build_usage([rec("channels-whatsapp-outbound", "5")])
        self.assertIsNone(usage["whatsapp"]["limit"])
        self.assertIsNone(usage["whatsapp"]["remaining"])

    def test_limit_from_env_gives_remaining_and_never_negative(self):
        with mock.patch.dict(os.environ, {"WHATSAPP_FREE_MONTHLY_LIMIT": "1000"}):
            self.assertEqual(nu.build_usage([rec("channels-whatsapp-outbound", "842")])["whatsapp"]["remaining"], 158)
            self.assertEqual(nu.build_usage([rec("channels-whatsapp-outbound", "1200")])["whatsapp"]["remaining"], 0)

    def test_garbage_limit_is_ignored(self):
        with mock.patch.dict(os.environ, {"WHATSAPP_FREE_MONTHLY_LIMIT": "abc"}):
            self.assertIsNone(nu.build_usage([])["whatsapp"]["limit"])

    def test_zero_when_provider_has_no_records(self):
        self.assertEqual(nu.build_usage([])["whatsapp"]["outboundMessages"], 0)


class RouteTest(unittest.TestCase):
    def setUp(self):
        nu._cache.update(at=0.0, payload=None)
        app = FastAPI()
        app.include_router(routes.router)
        self.client = TestClient(app)

    def test_provider_failure_degrades_to_ok_false(self):
        with mock.patch.object(nu, "_twilio_client", side_effect=ValueError("no creds")):
            body = self.client.get("/notifications/usage").json()
        self.assertEqual(body["ok"], False)

    def test_result_is_cached(self):
        fake = mock.MagicMock()
        fake.usage.records.this_month.list.return_value = [rec("channels-whatsapp-outbound", "3")]
        with mock.patch.object(nu, "_twilio_client", return_value=fake):
            self.client.get("/notifications/usage")
            body = self.client.get("/notifications/usage").json()
        self.assertEqual(body["whatsapp"]["outboundMessages"], 3)
        self.assertEqual(fake.usage.records.this_month.list.call_count, 1)


if __name__ == "__main__":
    unittest.main()
