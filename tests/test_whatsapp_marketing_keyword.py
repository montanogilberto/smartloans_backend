"""
WhatsApp BAJA/ALTA: marketing consent from the sender's own number.

A message that is just BAJA/STOP/ALTO/CANCELAR (or ALTA) updates
clientContactPreferences through sp_clientContactPreferences action 4 and is
answered with a fixed confirmation, even when the bot is off; it never
reaches the agent. Anything else goes to the bot as before.
No database / no Meta / no agent: everything external is stubbed.

Run:  venv/bin/python -m unittest tests/test_whatsapp_marketing_keyword.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.clientContactPreferences as ccp  # noqa: E402
import modules.whatsappCloud as wc  # noqa: E402

CHANNEL = {"channelId": 3, "companyId": 1, "branchId": None, "phoneNumberId": "1330937783442101",
           "botEnabled": True}
PHONE = "+526621234567"


def _msg(text):
    return {"phoneNumberId": CHANNEL["phoneNumberId"], "from": "5216621234567", "name": "Ana",
            "text": text, "type": "text", "messageId": "wamid.1"}


class KeywordParsingTest(unittest.TestCase):
    def test_only_a_bare_keyword_counts(self):
        self.assertEqual(ccp._keyword("  baja. "), "BAJA")
        self.assertEqual(ccp._keyword("Cancelár!"), "CANCELAR")
        self.assertNotIn(ccp._keyword("no me den de baja"), ccp.OPT_OUT_KEYWORDS)
        self.assertEqual(ccp._keyword(None), "")


class HandleKeywordTest(unittest.TestCase):
    def setUp(self):
        self.sp_result = {"result": [{"value": "1", "msg": "Saved Successfully", "error": ""}]}
        self.calls = []

        def fake_exec(sp_name, json_file):
            self.calls.append((sp_name, json_file))
            return self.sp_result
        for p in (mock.patch.object(ccp, "_exec", side_effect=fake_exec),
                  mock.patch.object(ccp, "log_workflow_step")):
            p.start()
            self.addCleanup(p.stop)

    def test_opt_out_resolves_by_phone_in_the_channel_company(self):
        self.assertEqual(ccp.handle_keyword(1, PHONE, "STOP"), ccp.OPT_OUT_REPLY)
        sp_name, body = self.calls[0]
        self.assertEqual(sp_name, "sp_clientContactPreferences")
        self.assertEqual(body["clientContactPreferences"][0],
                         {"action": 4, "companyId": 1, "phone": PHONE, "marketingOptIn": 0})

    def test_opt_in(self):
        self.assertEqual(ccp.handle_keyword(1, PHONE, "Alta"), ccp.OPT_IN_REPLY)
        self.assertEqual(self.calls[0][1]["clientContactPreferences"][0]["marketingOptIn"], 1)

    def test_opt_in_from_unknown_number(self):
        self.sp_result = {"result": [{"value": "0", "msg": "Saved Successfully", "error": ""}]}
        self.assertEqual(ccp.handle_keyword(1, PHONE, "ALTA"), ccp.OPT_IN_NOT_FOUND_REPLY)

    def test_opt_out_from_unknown_number_still_confirms(self):
        self.sp_result = {"result": [{"value": "0", "msg": "Saved Successfully", "error": ""}]}
        self.assertEqual(ccp.handle_keyword(1, PHONE, "BAJA"), ccp.OPT_OUT_REPLY)

    def test_sp_error_answers_failure_not_success(self):
        self.sp_result = {"result": [{"value": "", "msg": "boom", "error": "1"}]}
        with self.assertLogs(ccp.logger, "ERROR") as logs:
            self.assertEqual(ccp.handle_keyword(1, PHONE, "BAJA"), ccp.FAILED_REPLY)
        self.assertNotIn(PHONE, "".join(logs.output))  # the phone is never logged

    def test_not_a_keyword_touches_nothing(self):
        self.assertIsNone(ccp.handle_keyword(1, PHONE, "quiero agendar"))
        self.assertEqual(self.calls, [])


class WebhookHookTest(unittest.TestCase):
    def setUp(self):
        self.channel = dict(CHANNEL)
        self.sent, self.agent = [], mock.Mock(return_value="¿En qué te ayudo?")
        for p in (mock.patch.object(wc.whatsappChannels, "get_channel", lambda _id: self.channel),
                  mock.patch.object(wc, "log_message_to_database"),
                  mock.patch.object(wc, "send_text", lambda ch, to, body: self.sent.append((to, body))),
                  mock.patch.object(wc.whatsappReservations, "reply_to", self.agent),
                  mock.patch.object(ccp, "_exec", return_value={"result": [{"value": "1", "error": ""}]}),
                  mock.patch.object(ccp, "log_workflow_step")):
            p.start()
            self.addCleanup(p.stop)

    def test_keyword_is_answered_without_the_agent(self):
        wc._handle_message(_msg("BAJA"))
        self.assertEqual(self.sent, [(PHONE, ccp.OPT_OUT_REPLY)])
        self.agent.assert_not_called()

    def test_keyword_works_with_the_bot_off(self):
        self.channel["botEnabled"] = False
        wc._handle_message(_msg("baja"))
        self.assertEqual(self.sent, [(PHONE, ccp.OPT_OUT_REPLY)])

    def test_other_messages_still_reach_the_bot(self):
        wc._handle_message(_msg("hola"))
        self.agent.assert_called_once()
        self.assertEqual(self.sent, [(PHONE, "¿En qué te ayudo?")])

    def test_bot_off_and_not_a_keyword_stays_silent(self):
        self.channel["botEnabled"] = False
        wc._handle_message(_msg("hola"))
        self.assertEqual(self.sent, [])
        self.agent.assert_not_called()


if __name__ == "__main__":
    unittest.main()
