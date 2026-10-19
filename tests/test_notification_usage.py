"""
Provider usage for the Notifications screen — pure counting/payload + route/fallback.

Run:  venv/bin/python -m unittest tests/test_notification_usage.py -v
"""
import os
import sys
import unittest
from datetime import datetime, timezone
from types import SimpleNamespace as R
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.notificationUsage as nu  # noqa: E402
import routes_.notificationUsage as routes  # noqa: E402


def msg(status, to="+526620000000", direction="outbound-api"):
    return R(status=status, to=to, direction=direction)


def wa(status):
    return msg(status, to="whatsapp:+526620000000")


SINCE = datetime(2026, 10, 1, 7, tzinfo=timezone.utc)


class CountMessagesTest(unittest.TestCase):
    def test_groups_by_channel_and_final_status(self):
        counts = nu.count_messages([
            msg("delivered"), msg("delivered"), msg("failed"), msg("sent"), msg("queued"),
            wa("failed"), wa("undelivered"), wa("read"),
        ])
        self.assertEqual(counts["sms"], {"delivered": 2, "failed": 1, "inFlight": 2, "total": 5})
        self.assertEqual(counts["whatsapp"], {"delivered": 1, "failed": 2, "inFlight": 0, "total": 3})

    def test_inbound_is_ignored(self):
        counts = nu.count_messages([
            msg("received", direction="inbound"),
            R(status="received", to="whatsapp:+526620000000", direction="inbound"),
        ])
        self.assertEqual(counts["sms"]["total"], 0)
        self.assertEqual(counts["whatsapp"]["total"], 0)

    def test_unpriced_delivered_sms_still_counts(self):
        # October 2026: delivered SMS with price=None were invisible to Usage Records.
        m = R(status="delivered", to="+526620000000", direction="outbound-api", price=None)
        self.assertEqual(nu.count_messages([m])["sms"]["delivered"], 1)


class MonthStartTest(unittest.TestCase):
    def test_hermosillo_month_start_in_utc(self):
        self.assertEqual(nu.month_start(datetime(2026, 10, 18, 20, tzinfo=timezone.utc)), SINCE)

    def test_first_hours_utc_still_belong_to_previous_hermosillo_month(self):
        self.assertEqual(nu.month_start(datetime(2026, 11, 1, 3, tzinfo=timezone.utc)), SINCE)


class BuildUsageTest(unittest.TestCase):
    def setUp(self):
        for k in ("WHATSAPP_FREE_MONTHLY_LIMIT", "WA_SENDER_PHONE_NUMBER_ID"):
            os.environ.pop(k, None)

    def test_no_limit_configured_is_null(self):
        self.assertIsNone(nu.build_usage(nu.count_messages([]), SINCE)["whatsappLimit"])

    def test_limit_from_env(self):
        with mock.patch.dict(os.environ, {"WHATSAPP_FREE_MONTHLY_LIMIT": "1000"}):
            self.assertEqual(nu.build_usage(nu.count_messages([]), SINCE)["whatsappLimit"], 1000)

    def test_garbage_limit_is_ignored(self):
        with mock.patch.dict(os.environ, {"WHATSAPP_FREE_MONTHLY_LIMIT": "abc"}):
            self.assertIsNone(nu.build_usage(nu.count_messages([]), SINCE)["whatsappLimit"])

    def test_whatsapp_provider_follows_meta_sender(self):
        self.assertEqual(nu.build_usage(nu.count_messages([]), SINCE)["whatsappProvider"], "none")
        with mock.patch.dict(os.environ, {"WA_SENDER_PHONE_NUMBER_ID": "123"}):
            self.assertEqual(nu.build_usage(nu.count_messages([]), SINCE)["whatsappProvider"], "meta")

    def test_payload_shape(self):
        body = nu.build_usage(nu.count_messages([msg("delivered")]), SINCE)
        self.assertEqual(body["since"], "2026-10-01T07:00:00Z")
        self.assertTrue(body["twilio"]["ok"])
        self.assertEqual(body["twilio"]["sms"]["delivered"], 1)


class RouteTest(unittest.TestCase):
    def setUp(self):
        nu._cache.update(at=0.0, payload=None)
        app = FastAPI()
        app.include_router(routes.router)
        self.client = TestClient(app)

    def test_twilio_failure_keeps_ok_and_flags_twilio(self):
        with mock.patch.object(nu, "_twilio_client", side_effect=ValueError("no creds")):
            body = self.client.get("/notifications/usage").json()
        self.assertTrue(body["ok"])
        self.assertFalse(body["twilio"]["ok"])
        self.assertIsNone(nu._cache["payload"])

    def test_result_is_cached(self):
        fake = mock.MagicMock()
        fake.messages.list.return_value = [msg("delivered")]
        with mock.patch.object(nu, "_twilio_client", return_value=fake):
            self.client.get("/notifications/usage")
            body = self.client.get("/notifications/usage").json()
        self.assertEqual(body["twilio"]["sms"]["delivered"], 1)
        self.assertEqual(fake.messages.list.call_count, 1)


if __name__ == "__main__":
    unittest.main()
