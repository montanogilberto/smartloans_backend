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
            "log_msg": mock.patch.object(wc, "_record_outbound"),
            "log_step": mock.patch.object(wc, "log_workflow_step"),
        }
        self.m = {k: p.start() for k, p in patches.items()}
        self.addCleanup(mock.patch.stopall)

    def test_sends_from_the_customers_number_and_logs(self):
        res = wc.staff_reply(_req())
        self.assertEqual(res.status_code, 200)
        self.m["send"].assert_called_once_with(CHANNEL, "+5216621234567", "Hola, ya está lista tu ropa")
        kw = self.m["log_msg"].call_args.kwargs
        self.assertEqual((kw["status"], kw["response_body"], kw["wamid"], kw["sender_kind"]),
                         ("staff_sent", "userId=9", "wamid.X", "staff_pos"))
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


class OtherNumberTest(unittest.TestCase):
    """The lookup picked a number the customer isn't writing to: Meta refuses it,
    so the reply goes from the company's other number."""

    def setUp(self):
        self.lookup = {"result": [{"channelId": 3, "phoneNumberId": "PNID",
                                   "customerPhone": "+5216621234567", "lastInboundUtc": _ago(hours=2)}]}
        self.other = {"channelId": 2, "companyId": 1, "phoneNumberId": "OTHER", "isActive": True}
        patches = {
            "sp": mock.patch.object(wc, "assistant_sp", side_effect=lambda *_: self.lookup),
            "get_channel": mock.patch.object(wc.whatsappChannels, "get_channel", return_value=dict(CHANNEL)),
            "list": mock.patch.object(wc.whatsappChannels, "company_channels",
                                      return_value=[dict(CHANNEL, isActive=True), self.other]),
            "send": mock.patch.object(wc, "send_text"),
            "log_msg": mock.patch.object(wc, "_record_outbound"),
            "log_step": mock.patch.object(wc, "log_workflow_step"),
        }
        self.m = {k: p.start() for k, p in patches.items()}
        self.addCleanup(mock.patch.stopall)

    def test_a_refused_number_falls_back_to_the_other(self):
        self.m["send"].side_effect = [RuntimeError("WhatsApp Cloud send failed (400)"), {"messageId": "wamid.OK"}]
        self.assertEqual(wc.staff_reply(_req()).status_code, 200)
        self.assertEqual([c.args[0]["phoneNumberId"] for c in self.m["send"].call_args_list], ["PNID", "OTHER"])
        self.m["list"].assert_called_once_with(1)

    def test_the_first_number_working_never_lists_the_others(self):
        self.m["send"].return_value = {"messageId": "wamid.OK"}
        self.assertEqual(wc.staff_reply(_req()).status_code, 200)
        self.m["list"].assert_not_called()

    def test_the_app_gets_each_refusal_with_digits_masked(self):
        self.m["send"].side_effect = RuntimeError(
            "WhatsApp Cloud send failed (400): {'code': 131030, 'message': 'Recipient 526621234567 not in allowed list'}")
        res = wc.staff_reply(_req())
        attempts = __import__("json").loads(res.body)["attempts"]
        self.assertEqual([a["number"] for a in attempts], ["PNID"[-4:], "THER"])
        self.assertIn("131030", attempts[0]["result"])
        self.assertNotIn("6621234567", res.body.decode())

    def test_every_number_refused_is_502(self):
        self.m["send"].side_effect = RuntimeError("WhatsApp Cloud send failed (400)")
        self.assertEqual(wc.staff_reply(_req()).status_code, 502)
        self.assertEqual(self.m["send"].call_count, 2)
        self.m["log_msg"].assert_not_called()


class StaffTemplateTest(unittest.TestCase):
    """Staff write first (asTemplate): outside the 24 h window the text goes in
    mensaje_negocio; inside it, it is still plain text."""

    def setUp(self):
        self.lookup = {"result": [{"channelId": 3, "phoneNumberId": "PNID",
                                   "customerPhone": "+5216621234567", "lastInboundUtc": _ago(hours=30)}]}
        patches = {
            "sp": mock.patch.object(wc, "assistant_sp", side_effect=lambda *_: self.lookup),
            "get_channel": mock.patch.object(wc.whatsappChannels, "get_channel", return_value=dict(CHANNEL)),
            "send": mock.patch.object(wc, "send_text", return_value={"messageId": "wamid.X"}),
            "template": mock.patch.object(wc, "send_template", return_value={"messageId": "wamid.T"}),
            "outbound": mock.patch.object(wc, "outbound_channel", return_value={"phoneNumberId": "SENDER"}),
            "company": mock.patch("modules.companies.company_name", return_value="Lavanderia GMO"),
            "log_msg": mock.patch.object(wc, "_record_outbound"),
            "log_step": mock.patch.object(wc, "log_workflow_step"),
        }
        self.m = {k: p.start() for k, p in patches.items()}
        self.addCleanup(mock.patch.stopall)

    def _send(self, **over):
        res = wc.staff_reply(_req(asTemplate=True, **over))
        return res.status_code, __import__("json").loads(res.body)

    def test_outside_24h_goes_as_template_from_the_clients_number(self):
        status, body = self._send()
        self.assertEqual((status, body["viaTemplate"]), (200, True))
        self.m["template"].assert_called_once_with(CHANNEL, "+5216621234567", "mensaje_negocio",
                                                   ["Lavanderia GMO", "Hola, ya está lista tu ropa"])
        self.m["send"].assert_not_called()
        self.assertIn("template=mensaje_negocio", self.m["log_msg"].call_args.kwargs["response_body"])

    def test_a_client_who_never_wrote_gets_it_from_the_business_number(self):
        self.lookup = {"result": []}
        status, _ = self._send()
        self.assertEqual(status, 200)
        sender, to = self.m["template"].call_args.args[:2]
        self.assertEqual((sender, to), ({"phoneNumberId": "SENDER"}, "+526621234567"))

    def test_inside_the_window_it_is_plain_text(self):
        self.lookup["result"][0]["lastInboundUtc"] = _ago(hours=1)
        status, body = self._send()
        self.assertEqual((status, body["viaTemplate"]), (200, False))
        self.m["template"].assert_not_called()

    def test_without_the_flag_nothing_is_sent_as_template(self):
        self.assertEqual(wc.staff_reply(_req()).status_code, 409)
        self.m["template"].assert_not_called()

    def test_too_long_for_a_template(self):
        status, body = self._send(body="x" * 901)
        self.assertEqual((status, body["error"]), (400, "too_long_for_template"))

    def test_meta_refusal_is_template_failed(self):
        self.m["template"].side_effect = RuntimeError("132001 template does not exist")
        status, body = self._send()
        self.assertEqual((status, body["error"]), (502, "template_failed"))
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
