"""
Delivery status for notification dispatches + walk-in skip.

Found 2026-10-12: all 152 WhatsApp messages of the previous 30 days failed at
Twilio (63005: WhatsApp rejected free-form text) while every dispatch row said
"sent" — Twilio was never told where to report status, and the callback never
touched notificationDispatches. Also 43 of 166 dispatches went to clientId 1,
the walk-in placeholder. No database / no Twilio: SPs and HTTP are stubbed.

Run:  venv/bin/python -m unittest tests/test_dispatch_delivery_status.py -v
"""
import asyncio
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from twilio.request_validator import RequestValidator  # noqa: E402

import modules.notificationDispatch as nd  # noqa: E402
import modules.ticket_notifications as tn  # noqa: E402
import routes_.whatsapp as wa_routes  # noqa: E402

TOKEN = "test-auth-token"


def run(coro):
    return asyncio.new_event_loop().run_until_complete(coro)


class StatusMappingTest(unittest.TestCase):
    def test_terminal_states(self):
        self.assertEqual(nd.dispatch_status_for("delivered"), "confirmed")
        self.assertEqual(nd.dispatch_status_for("read"), "confirmed")
        self.assertEqual(nd.dispatch_status_for("failed"), "failed")
        self.assertEqual(nd.dispatch_status_for("UNDELIVERED"), "failed")

    def test_in_flight_states_are_ignored(self):
        for s in ("queued", "sending", "sent", "accepted", "", None):
            self.assertIsNone(nd.dispatch_status_for(s))


class ApplyProviderStatusTest(unittest.TestCase):
    def setUp(self):
        self.updates = []
        self.lookups = []
        self.rows = [[{"notificationDispatchId": 120, "companyId": 1}]]
        patches = [
            mock.patch.object(nd, "connection", return_value=mock.MagicMock()),
            mock.patch.object(nd, "_lookup", side_effect=self._lookup),
            mock.patch.object(nd, "notificationDispatch_sp", side_effect=self._update),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def _lookup(self, cursor, item):
        self.lookups.append(item)
        return self.rows.pop(0) if self.rows else []

    def _update(self, payload):
        self.updates.append(payload["notificationDispatches"][0])
        return mock.MagicMock(status_code=200)

    def test_failed_marks_the_row_failed_with_failedAt(self):
        out = run(nd.apply_provider_status("SM09e9", "failed", retry_delay_s=0))
        self.assertEqual(out, {"updated": True, "notificationDispatchId": 120, "status": "failed"})
        row = self.updates[0]
        self.assertEqual((row["action"], row["status"], row["companyId"]), (2, "failed", 1))
        self.assertIsNotNone(row["failedAt"])
        self.assertIsNone(row["confirmedAt"])
        self.assertEqual(self.lookups[0], {"action": "byProviderMessageId", "providerMessageId": "SM09e9"})

    def test_failed_stores_provider_error_and_sql_parsable_failedAt(self):
        run(nd.apply_provider_status("SM09e9", "failed", retry_delay_s=0,
                                     error_code="63016", error_message="Outside the 24h window"))
        row = self.updates[0]
        self.assertEqual((row["providerErrorCode"], row["providerErrorMessage"]),
                         ("63016", "Outside the 24h window"))
        # DATETIME can't parse '+00:00' or 6-digit fractions (stored NULL before).
        self.assertRegex(row["failedAt"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}$")

    def test_confirmed_never_carries_an_error(self):
        run(nd.apply_provider_status("SM09e9", "delivered", retry_delay_s=0, error_code="63016"))
        self.assertIsNone(self.updates[0]["providerErrorCode"])

    def test_delivered_marks_confirmed(self):
        run(nd.apply_provider_status("SM09e9", "delivered", retry_delay_s=0))
        self.assertEqual(self.updates[0]["status"], "confirmed")
        self.assertIsNotNone(self.updates[0]["confirmedAt"])

    def test_in_flight_status_touches_nothing(self):
        out = run(nd.apply_provider_status("SM09e9", "sent", retry_delay_s=0))
        self.assertEqual(out["reason"], "not_terminal")
        self.assertEqual((self.lookups, self.updates), ([], []))

    def test_callback_before_row_exists_is_retried_once(self):
        self.rows = [[], [{"notificationDispatchId": 7, "companyId": 1}]]
        out = run(nd.apply_provider_status("SMx", "failed", retry_delay_s=0))
        self.assertEqual((len(self.lookups), out["notificationDispatchId"]), (2, 7))

    def test_unknown_sid_is_a_noop(self):
        self.rows = [[], []]
        out = run(nd.apply_provider_status("SMnope", "failed", retry_delay_s=0))
        self.assertEqual((out["reason"], self.updates), ("no_dispatch", []))


class WalkInTest(unittest.TestCase):
    def test_is_walk_in(self):
        self.assertTrue(nd.is_walk_in("client", 1))
        self.assertTrue(nd.is_walk_in("client", "1"))
        self.assertFalse(nd.is_walk_in("client", 2260))
        self.assertFalse(nd.is_walk_in("user", 1))      # userId 1 is a real account

    def test_dispatch_to_walk_in_sends_nothing_and_writes_nothing(self):
        with mock.patch.object(nd, "connection") as conn, \
             mock.patch.object(nd, "send_whatsapp") as wa, \
             mock.patch.object(nd, "send_azure_push") as push:
            resp = run(nd.dispatch_notification_connector({
                "companyId": 1, "sourceType": "income", "sourceId": 4900, "recipientType": "client",
                "recipientId": 1, "eventName": "income_created", "messagePreview": "x"}))
        self.assertEqual(resp.status_code, 200)
        self.assertIn(b"walk_in_client", resp.body)
        conn.assert_not_called()
        wa.assert_not_called()
        push.assert_not_called()


class CallbackUrlTest(unittest.TestCase):
    def test_defaults_to_this_backend(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("TWILIO_WHATSAPP_STATUS_CALLBACK_URL", None)
            os.environ.pop("BACKEND_PUBLIC_URL", None)
            self.assertEqual(tn.whatsapp_status_callback_url(),
                             "https://smartloansbackend.azurewebsites.net/whatsapp/status")

    def test_explicit_env_wins(self):
        with mock.patch.dict(os.environ, {"TWILIO_WHATSAPP_STATUS_CALLBACK_URL": "https://x.test/cb"}):
            self.assertEqual(tn.whatsapp_status_callback_url(), "https://x.test/cb")


class StatusCallbackRouteTest(unittest.TestCase):
    URL = "https://smartloansbackend.azurewebsites.net/whatsapp/status"
    FORM = {"MessageSid": "SM09e9", "MessageStatus": "failed", "ErrorCode": "63005",
            "To": "whatsapp:+526624737005", "From": "whatsapp:+14155238886"}

    def setUp(self):
        app = FastAPI()
        app.include_router(wa_routes.router)
        self.client = TestClient(app)
        patches = [
            mock.patch.dict(os.environ, {"TWILIO_AUTH_TOKEN": TOKEN}),
            mock.patch.object(wa_routes, "log_message_to_database"),
            mock.patch.object(wa_routes, "whatsapp_status_callback_url", return_value=self.URL),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.apply = mock.AsyncMock(return_value={"updated": True})
        p = mock.patch.object(wa_routes, "apply_provider_status", self.apply)
        p.start()
        self.addCleanup(p.stop)

    def _post(self, signature):
        headers = {"X-Twilio-Signature": signature} if signature else {}
        return self.client.post("/whatsapp/status", data=self.FORM, headers=headers)

    def test_signed_failed_callback_updates_the_dispatch(self):
        sig = RequestValidator(TOKEN).compute_signature(self.URL, self.FORM)
        resp = self._post(sig)
        self.assertEqual(resp.status_code, 200)
        self.apply.assert_awaited_once_with("SM09e9", "failed", error_code="63005", error_message=None)

    def test_unsigned_or_forged_callback_is_logged_but_never_updates(self):
        for sig in (None, "forged"):
            self.apply.reset_mock()
            resp = self._post(sig)
            self.assertEqual(resp.status_code, 200)    # always ack Twilio
            self.apply.assert_not_awaited()



class MetaStatusWebhookTest(unittest.TestCase):
    """The production route: WhatsApp Cloud API (Meta). Its delivery receipts
    arrive in the signed /whatsapp/cloud/webhook as value.statuses."""

    @staticmethod
    def payload(*statuses):
        return {"entry": [{"changes": [{"field": "messages", "value": {"statuses": [
            {"id": wamid, "status": st, "recipient_id": "526624737005"} for wamid, st in statuses]}}]}]}

    def test_delivered_read_failed_update_the_dispatch_sent_does_not(self):
        import modules.whatsappCloud as wc
        apply = mock.AsyncMock(return_value={"updated": True})
        with mock.patch.object(nd, "apply_provider_status", apply):
            wc._log_statuses(self.payload(("wamid.A", "sent"), ("wamid.A", "delivered"),
                                          ("wamid.B", "read"), ("wamid.C", "failed")))
        self.assertEqual([c.args for c in apply.await_args_list],
                         [("wamid.A", "delivered"), ("wamid.B", "read"), ("wamid.C", "failed")])

    def test_a_dispatch_update_error_never_breaks_the_webhook(self):
        import modules.whatsappCloud as wc
        with mock.patch.object(nd, "apply_provider_status", mock.AsyncMock(side_effect=RuntimeError("db down"))):
            wc._log_statuses(self.payload(("wamid.A", "delivered")))   # must not raise


if __name__ == "__main__":
    unittest.main()
