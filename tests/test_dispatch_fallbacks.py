"""
Push -> WhatsApp -> SMS: the two steps that let customers fall through.

Found 2026-10-20: (1) a client with an app account but no phone registered got
a "sent" push (the hub answers 2xx for a tag with no devices) and nothing else;
(2) a WhatsApp that Meta accepted and failed seconds later (131026) only marked
the row failed — 6 sales since Oct 16 got neither WhatsApp nor SMS.
No database / no hub / no Twilio: everything external is stubbed.

Run:  venv/bin/python -m unittest tests/test_dispatch_fallbacks.py -v
"""
import asyncio
import contextlib
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.azure_notifications as an  # noqa: E402
import modules.notificationDispatch as nd  # noqa: E402


def run(coro):
    return asyncio.new_event_loop().run_until_complete(coro)


HUB_ENV = {
    "AZURE_NOTIFICATION_HUB_CONNECTION_STRING":
        "Endpoint=sb://ns.servicebus.windows.net/;SharedAccessKeyName=k;SharedAccessKey=c2VjcmV0",
    "AZURE_NOTIFICATION_HUB_NAME": "hub",
}


def _feed(*descriptions):
    entries = "".join(
        f"<entry><content><{d} xmlns='x'><Tags>user_29</Tags></{d}></content></entry>" for d in descriptions)
    return f"<?xml version='1.0'?><feed xmlns='http://www.w3.org/2005/Atom'>{entries}</feed>"


class HasPushDeviceTest(unittest.TestCase):
    def check(self, body, status=200, fmt="fcmv1"):
        response = mock.MagicMock(status_code=status, text=body)
        client = mock.MagicMock()
        client.__aenter__ = mock.AsyncMock(return_value=client)
        client.__aexit__ = mock.AsyncMock(return_value=False)
        client.get = mock.AsyncMock(return_value=response)
        with mock.patch.dict(os.environ, {**HUB_ENV, "AZURE_NOTIFICATION_HUB_FORMAT": fmt}), \
             mock.patch.object(an.httpx, "AsyncClient", return_value=client):
            out = run(an.has_push_device(29))
        url = client.get.await_args.args[0]
        self.assertEqual(url, "https://ns.servicebus.windows.net/hub/tags/user_29/registrations?api-version=2015-01")
        return out

    def test_android_device_is_registered(self):
        out = self.check(_feed("FcmV1RegistrationDescription"))
        self.assertEqual((out["registered"], out["platforms"]), (True, ["FcmV1"]))

    def test_template_registrations_count_too(self):
        self.assertTrue(self.check(_feed("FcmV1TemplateRegistrationDescription"))["registered"])

    def test_empty_feed_is_no_device(self):
        out = self.check(_feed())
        self.assertEqual((out["registered"], out["reason"]), (False, "no_registration"))

    def test_iphone_only_is_no_device_while_we_send_android_only(self):
        out = self.check(_feed("AppleRegistrationDescription"), fmt="fcmv1")
        self.assertEqual((out["registered"], out["reason"]), (False, "platform_not_sent"))
        self.assertTrue(self.check(_feed("AppleRegistrationDescription"), fmt="all")["registered"])

    def test_hub_error_is_no_device(self):
        out = self.check("<Error/>", status=401)
        self.assertEqual((out["registered"], out["reason"]), (False, "lookup_status_401"))

    def test_missing_config_never_calls_the_hub(self):
        with mock.patch.dict(os.environ, {"AZURE_NOTIFICATION_HUB_CONNECTION_STRING": ""}), \
             mock.patch.object(an.httpx, "AsyncClient") as client:
            out = run(an.has_push_device(29))
        self.assertEqual((out["registered"], out["reason"]), (False, "missing_config"))
        client.assert_not_called()


@contextlib.contextmanager
def _span(*args, **kwargs):
    yield mock.MagicMock()


class CascadeNoDeviceTest(unittest.TestCase):
    """Client 1020 has an app account (user 29) but the hub has no phone for it."""

    def setUp(self):
        self.rows = []
        patches = [
            mock.patch.object(nd, "connection", return_value=mock.MagicMock()),
            mock.patch.object(nd, "_existing_resolved_dispatch", return_value=None),
            mock.patch.object(nd, "_get_policy", return_value={
                "channels": ["push", "whatsapp", "sms"], "allow_sms_fallback": True}),
            mock.patch.object(nd, "_resolve_push_user_id", return_value=29),
            mock.patch.object(nd, "notificationDispatch_sp",
                              side_effect=lambda p: self.rows.append(p["notificationDispatches"][0])),
            mock.patch.object(nd, "log_workflow_step"),
            mock.patch.object(nd, "timed_integration", _span),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def dispatch(self):
        return run(nd.dispatch_notification_connector({
            "companyId": 1, "sourceType": "income", "sourceId": 5948, "recipientType": "client",
            "recipientId": 1020, "eventName": "income_created", "phone": "+526620000000",
            "messagePreview": "Gracias por su compra. Total: $3.00 MXN",
        }))

    def test_no_registered_device_skips_push_and_sends_whatsapp(self):
        with mock.patch.object(nd, "has_push_device", mock.AsyncMock(return_value={
                 "registered": False, "platforms": [], "reason": "no_registration"})), \
             mock.patch.object(nd, "send_azure_push", mock.AsyncMock()) as push, \
             mock.patch.object(nd, "send_whatsapp", return_value={"provider": "meta", "messageId": "wamid.1"}):
            self.dispatch()
        push.assert_not_awaited()
        row = self.rows[0]
        attempted = json.loads(row["attemptedChannels"])
        self.assertEqual([(a["channel"], a["outcome"]) for a in attempted],
                         [("push", "NO_DEVICE"), ("whatsapp", "SENT")])
        self.assertEqual(attempted[0]["detail"], "no_registration")
        self.assertEqual((row["selectedChannel"], row["fallbackReason"]), ("whatsapp", "NO_DEVICE"))

    def test_registered_device_gets_the_push_and_stops(self):
        with mock.patch.object(nd, "has_push_device", mock.AsyncMock(return_value={
                 "registered": True, "platforms": ["FcmV1"], "reason": "ok"})), \
             mock.patch.object(nd, "send_azure_push", mock.AsyncMock(return_value={"sent": True})) as push, \
             mock.patch.object(nd, "send_whatsapp") as wa:
            self.dispatch()
        push.assert_awaited_once()
        wa.assert_not_called()
        self.assertEqual(self.rows[0]["selectedChannel"], "push")


class SmsAfterWhatsappFailureTest(unittest.TestCase):
    """Dispatch 1204: Meta took the WhatsApp, then reported 131026."""

    ROW = {"notificationDispatchId": 1204, "companyId": 1, "sourceType": "income", "sourceId": 5963,
           "recipientType": "client", "recipientId": 2290, "eventName": "income_created",
           "preferredChannel": "push", "selectedChannel": "whatsapp", "status": "failed",
           "messagePreview": "Gracias por su compra. Total: $180.00 MXN\nPuntos: +4.50"}

    def setUp(self):
        self.inserts = []
        self.row = dict(self.ROW)
        self.policy = {"channels": ["push", "whatsapp", "sms"], "allow_sms_fallback": True}
        self.resolved = None
        patches = [
            mock.patch.object(nd, "_dispatch_row", side_effect=lambda _id: self.row),
            mock.patch.object(nd, "connection", return_value=mock.MagicMock()),
            mock.patch.object(nd, "_get_policy", side_effect=lambda c, e: self.policy),
            mock.patch.object(nd, "_existing_resolved_dispatch", side_effect=lambda *a: self.resolved),
            mock.patch.object(nd, "_client_phone", return_value="+529211234567"),
            mock.patch.object(nd, "notificationDispatch_sp",
                              side_effect=lambda p: self.inserts.append(p["notificationDispatches"][0])),
            mock.patch.object(nd, "log_workflow_step"),
            mock.patch.object(nd, "timed_integration", _span),
            mock.patch("modules.receiptLinks.receipt_link", return_value="https://b.test/recibo/1-5963-sig"),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def test_sends_the_same_text_with_the_ticket_link_and_logs_a_new_row(self):
        with mock.patch.object(nd, "send_sms", return_value={"messageSid": "SM1"}) as sms:
            out = run(nd.sms_after_whatsapp_failure(1204, "131026"))
        self.assertEqual(out, {"sent": True, "reason": "ok"})
        sms.assert_called_once_with(
            "+529211234567",
            "Gracias por su compra. Total: $180.00 MXN\nPuntos: +4.50\nVer su ticket: https://b.test/recibo/1-5963-sig")
        row = self.inserts[0]
        self.assertEqual((row["action"], row["selectedChannel"], row["status"], row["fallbackReason"],
                          row["providerMessageId"], row["sourceId"]),
                         (1, "sms", "sent", "WHATSAPP_FAILED", "SM1", 5963))
        attempted = json.loads(row["attemptedChannels"])
        self.assertEqual([(a["channel"], a["outcome"]) for a in attempted],
                         [("whatsapp", "FAILED_AFTER_SEND"), ("sms", "SENT")])
        self.assertEqual((attempted[0]["providerErrorCode"], attempted[0]["notificationDispatchId"]),
                         ("131026", 1204))

    def test_failed_sms_is_logged_as_failed(self):
        with mock.patch.object(nd, "send_sms", side_effect=RuntimeError("21211 invalid number")):
            out = run(nd.sms_after_whatsapp_failure(1204, "131026"))
        self.assertEqual(out["reason"], "sms_failed")
        self.assertEqual((self.inserts[0]["status"], self.inserts[0]["providerErrorMessage"]),
                         ("failed", "21211 invalid number"))

    def skipped(self, reason):
        with mock.patch.object(nd, "send_sms") as sms:
            out = run(nd.sms_after_whatsapp_failure(1204, "131026"))
        sms.assert_not_called()
        self.assertEqual((out, self.inserts), ({"sent": False, "reason": reason}, []))

    def test_duplicate_webhook_after_sms_went_out_sends_nothing(self):
        self.resolved = {"notificationDispatchId": 1205, "selectedChannel": "sms", "status": "sent"}
        self.skipped("already_resolved")

    def test_policy_without_sms_sends_nothing(self):
        self.policy = {"channels": ["push", "whatsapp"], "allow_sms_fallback": False}
        self.skipped("policy_no_sms")

    def test_a_failed_sms_row_is_not_retried_as_sms(self):
        self.row["selectedChannel"] = "sms"
        self.skipped("not_whatsapp")

    def test_walk_in_and_users_have_no_client_phone(self):
        self.row["recipientId"] = 1
        self.skipped("no_client_phone")
        self.row.update(recipientType="user", recipientId=29)
        self.skipped("no_client_phone")

    def test_never_raises(self):
        with mock.patch.object(nd, "_dispatch_row", side_effect=RuntimeError("db down")):
            out = run(nd.sms_after_whatsapp_failure(1204, "131026"))
        self.assertFalse(out["sent"])


if __name__ == "__main__":
    unittest.main()
