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
            "log_msg": mock.patch.object(wc, "log_message_to_database"),
            "log_step": mock.patch.object(wc, "log_workflow_step"),
        }
        self.m = {k: p.start() for k, p in patches.items()}
        self.addCleanup(mock.patch.stopall)

    def test_sends_from_the_customers_number_and_logs(self):
        res = wc.staff_reply(_req())
        self.assertEqual(res.status_code, 200)
        self.m["send"].assert_called_once_with(CHANNEL, "+5216621234567", "Hola, ya está lista tu ropa")
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

    def test_meta_failure_is_502_and_not_logged(self):
        self.m["send"].side_effect = RuntimeError("WhatsApp Cloud send failed (400)")
        self.assertEqual(wc.staff_reply(_req()).status_code, 502)
        self.m["log_msg"].assert_not_called()


if __name__ == "__main__":
    unittest.main()


class NeverPauseTest(unittest.TestCase):
    """Support is automatic (2026-11-02): nothing silences the agent in a chat."""

    def test_handoff_notifies_staff_without_pausing_the_agent(self):
        import modules.whatsappReservations as wr
        with mock.patch.object(wr.whatsappChannels, "pause_for_staff") as pause, \
             mock.patch.object(wr, "pushNotifications_sp", new=mock.AsyncMock()) as push:
            wr._hand_off_to_staff(dict(CHANNEL), "+5216621234567", "Ana", "quiere hablar con alguien")
        pause.assert_not_called()
        push.assert_called_once()

    def test_staff_echo_from_the_app_is_logged_not_paused(self):
        payload = {"entry": [{"changes": [{"field": "smb_message_echoes", "value": {
            "metadata": {"phone_number_id": "PNID"},
            "message_echoes": [{"to": "5216621234567", "text": {"body": "Ya está tu ropa"}}]}}]}]}
        with mock.patch.object(wc.whatsappChannels, "get_channel", return_value=dict(CHANNEL)), \
             mock.patch.object(wc.whatsappChannels, "pause_for_staff") as pause, \
             mock.patch.object(wc, "log_message_to_database") as log_msg:
            wc._log_staff_echoes(payload)
        pause.assert_not_called()
        self.assertEqual(log_msg.call_args.kwargs["status"], "staff_app")


class InboundMarksNumberTest(unittest.TestCase):
    """Every inbound message marks the number the customer wrote to, so the
    staff reply ('channel' lookup, ordered by updatedAt) uses that number and
    not the number of the customer's last booking (Meta answered 400)."""

    def test_inbound_touches_the_conversation_of_that_number(self):
        channel = {**CHANNEL, "botEnabled": False}
        msg = {"phoneNumberId": "PNID", "from": "5216621234567", "name": "Ana", "text": "hola",
               "type": "text", "messageId": "wamid.T1"}
        with mock.patch.object(wc.whatsappChannels, "get_channel", return_value=channel), \
             mock.patch.object(wc, "_record_ad_referral") as referral, \
             mock.patch.object(wc, "log_message_to_database"), \
             mock.patch.object(wc.clientContactPreferences, "handle_keyword", return_value=None), \
             mock.patch.object(wc.whatsappChannels, "touch") as touch:
            wc._handle_message(msg)
        touch.assert_called_once_with(3, "+526621234567")
        referral.assert_called_once()  # still before the touch: a first message is still a new lead

    def test_a_failed_touch_never_stops_the_message(self):
        with mock.patch.object(wc.whatsappChannels, "get_channel", return_value={**CHANNEL, "botEnabled": False}), \
             mock.patch.object(wc, "_record_ad_referral"), \
             mock.patch.object(wc, "log_message_to_database") as logged, \
             mock.patch.object(wc.clientContactPreferences, "handle_keyword", return_value=None), \
             mock.patch.object(wc.whatsappChannels, "touch", side_effect=RuntimeError("db down")):
            wc._handle_message({"phoneNumberId": "PNID", "from": "5216621234567", "text": "hola",
                                "type": "text", "messageId": "wamid.T2"})
        logged.assert_called_once()
