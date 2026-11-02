"""
POST /whatsapp/staffReply — a POS user answers a WhatsApp customer.

The SP lookup (sp_whatsappAgentConversations action "channel"), the channel
cache, Meta and the DB loggers are mocked: these tests check the guards
(input, company, Meta's 24 h window) and what happens after a send.

Run:  venv/bin/python -m unittest tests/test_whatsapp_staff_reply.py -v
"""
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.whatsappCloud as wc  # noqa: E402

CHANNEL = {"channelId": 3, "companyId": 1, "phoneNumberId": "PNID", "branchName": None}


def _ago(**kw) -> str:
    return (datetime.now(timezone.utc) - timedelta(**kw)).strftime("%Y-%m-%dT%H:%M:%S")


def _req(**over):
    row = {"companyId": 1, "userId": 9, "phone10": "6621234567", "body": "Hola, ya está lista tu ropa"}
    row.update(over)
    return {"whatsappStaffReply": [row]}


class StaffReplyTest(unittest.TestCase):
    def setUp(self):
        self.lookup = {"result": [{"channelId": 3, "phoneNumberId": "PNID",
                                   "customerPhone": "+5216621234567", "lastInboundUtc": _ago(hours=2)}]}
        patches = {
            "sp": mock.patch.object(wc, "assistant_sp", side_effect=lambda *_: self.lookup),
            "get_channel": mock.patch.object(wc.whatsappChannels, "get_channel", return_value=dict(CHANNEL)),
            "send": mock.patch.object(wc, "send_text", return_value={"messageId": "wamid.X"}),
            "pause": mock.patch.object(wc.whatsappReservations, "pause_for_staff"),
            "log_msg": mock.patch.object(wc, "log_message_to_database"),
            "log_step": mock.patch.object(wc, "log_workflow_step"),
        }
        self.m = {k: p.start() for k, p in patches.items()}
        self.addCleanup(mock.patch.stopall)

    def test_sends_from_the_customers_number_pauses_bot_and_logs(self):
        res = wc.staff_reply(_req())
        self.assertEqual(res.status_code, 200)
        self.m["send"].assert_called_once_with(CHANNEL, "+5216621234567", "Hola, ya está lista tu ropa")
        self.m["pause"].assert_called_once_with(CHANNEL, "+5216621234567")
        kw = self.m["log_msg"].call_args.kwargs
        self.assertEqual((kw["direction"], kw["status"], kw["response_body"]), ("outbound", "staff_sent", "userId=9"))
        # The workflow log carries no message text or phone.
        step = str(self.m["log_step"].call_args)
        self.assertNotIn("ropa", step)
        self.assertNotIn("6621234567", step)

    def test_outside_24h_is_refused_before_sending(self):
        self.lookup["result"][0]["lastInboundUtc"] = _ago(hours=25)
        res = wc.staff_reply(_req())
        self.assertEqual(res.status_code, 409)
        self.m["send"].assert_not_called()
        self.m["pause"].assert_not_called()

    def test_never_wrote_is_outside_window(self):
        self.lookup["result"][0]["lastInboundUtc"] = None
        self.assertEqual(wc.staff_reply(_req()).status_code, 409)

    def test_no_channel_for_company(self):
        self.lookup = {"result": []}
        self.assertEqual(wc.staff_reply(_req()).status_code, 404)
        self.m["send"].assert_not_called()

    def test_channel_of_another_company_is_refused(self):
        self.m["get_channel"].return_value = {**CHANNEL, "companyId": 2}
        self.assertEqual(wc.staff_reply(_req()).status_code, 404)
        self.m["send"].assert_not_called()

    def test_bad_input(self):
        for bad in (_req(body="  "), _req(phone10="12345"), _req(userId=None), _req(body="x" * 4097)):
            self.assertEqual(wc.staff_reply(bad).status_code, 400)
        self.m["send"].assert_not_called()

    def test_meta_failure_is_502_and_bot_not_paused(self):
        self.m["send"].side_effect = RuntimeError("WhatsApp Cloud send failed (400)")
        self.assertEqual(wc.staff_reply(_req()).status_code, 502)
        self.m["pause"].assert_not_called()
        self.m["log_msg"].assert_not_called()


if __name__ == "__main__":
    unittest.main()
