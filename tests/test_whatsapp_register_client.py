"""
WhatsApp bot: a customer registers themself as a client (REGISTER_CLIENT).

The agent's registration sub-agent proposes {"fullName"}; this module stores
it as the pending proposal WITH its capability, and on the customer's "sí"
re-checks the sender's phone and creates the client through sp_clients with
the channel's companyId and the sender's phone — never values from the agent.
No database / no Meta / no agent: everything external is stubbed.

Run:  venv/bin/python -m unittest tests/test_whatsapp_register_client.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.whatsappReservations as wr  # noqa: E402

CHANNEL = {"channelId": 3, "companyId": 1, "branchId": None, "phoneNumberId": "1330937783442101"}
PHONE = "+5216621234567"


class _Resp:
    def __init__(self, body):
        self.body = json.dumps(body).encode()


class RegisterClientTest(unittest.TestCase):
    def setUp(self):
        self.pending = None
        self.lookup = {"result": [{"status": "not_found"}]}
        self.created = {"result": [{"value": "", "msg": "Inserted Successfully", "error": "0"}]}
        self.agent = ("Te registro como *Ana López Ruiz* con este número de WhatsApp. ¿Confirmas?",
                      {"capability": "REGISTER_CLIENT", "fields": {"fullName": "Ana López Ruiz"}})
        self.clients_calls = []
        self.set_pending = mock.MagicMock()
        patches = [
            mock.patch.object(wr, "AGENT_URL", "https://agent.test"),
            mock.patch.object(wr.whatsappChannels, "get_state", side_effect=lambda *a: {
                "staffPaused": False, "pending": self.pending, "lastBooked": None}),
            mock.patch.object(wr.whatsappChannels, "set_pending", self.set_pending),
            mock.patch.object(wr.whatsappChannels, "clear_pending"),
            mock.patch.object(wr, "_ask_agent", side_effect=lambda *a: self.agent),
            mock.patch.object(wr, "assistant_sp", side_effect=lambda proc, payload: self.lookup),
            mock.patch.object(wr, "clients_sp", side_effect=self._clients_sp),
            mock.patch.object(wr, "_book", side_effect=AssertionError("must not book")),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def _clients_sp(self, payload):
        self.clients_calls.append(payload)
        return _Resp(self.created)

    def test_proposal_is_stored_with_its_capability_and_name_only(self):
        self.agent = (self.agent[0], {"capability": "REGISTER_CLIENT",
                                      "fields": {"fullName": "Ana López Ruiz", "cellphone": "5550000000"}})
        out = wr.reply_to(CHANNEL, PHONE, "Ana", "Ana López Ruiz")
        self.assertIn("¿Confirmas?", out)
        stored = self.set_pending.call_args.args[2]
        self.assertEqual(stored, {"capability": "REGISTER_CLIENT", "fullName": "Ana López Ruiz"})
        self.assertEqual(self.clients_calls, [])

    def test_si_creates_the_client_with_trusted_company_and_phone(self):
        self.pending = {"capability": "REGISTER_CLIENT", "fullName": "ana lópez ruiz"}
        out = wr.reply_to(CHANNEL, PHONE, "Ana", "sí")
        self.assertIn("quedaste registrado", out)
        row = self.clients_calls[0]["clients"][0]
        self.assertEqual(row, {"action": 1, "first_name": "Ana", "last_name": "López Ruiz",
                               "clientType": "pos", "companyId": 1, "cellphone": "6621234567"})

    def test_already_registered_number_is_not_created_again(self):
        self.pending = {"capability": "REGISTER_CLIENT", "fullName": "Ana López"}
        self.lookup = {"result": [{"status": "found", "clientId": 9, "firstName": "Anita"}]}
        out = wr.reply_to(CHANNEL, PHONE, "Ana", "sí")
        self.assertIn("ya está registrado", out)
        self.assertEqual(self.clients_calls, [])

    def test_ambiguous_number_goes_to_the_counter(self):
        self.pending = {"capability": "REGISTER_CLIENT", "fullName": "Ana López"}
        self.lookup = {"result": [{"status": "ambiguous"}]}
        self.assertEqual(wr.reply_to(CHANNEL, PHONE, "Ana", "sí"), wr._REGISTER_AMBIGUOUS)
        self.assertEqual(self.clients_calls, [])

    def test_lookup_failure_does_not_create(self):
        self.pending = {"capability": "REGISTER_CLIENT", "fullName": "Ana López"}
        self.lookup = {"result": [{}]}
        self.assertEqual(wr.reply_to(CHANNEL, PHONE, "Ana", "sí"), wr._REGISTER_FAILED)
        self.assertEqual(self.clients_calls, [])

    def test_sp_refusal_for_existing_cellphone_reads_as_registered(self):
        self.pending = {"capability": "REGISTER_CLIENT", "fullName": "Ana López"}
        self.created = {"result": [{"value": "", "msg": "Cellphone already exists.", "error": "1"}]}
        self.assertIn("ya está registrado", wr.reply_to(CHANNEL, PHONE, "Ana", "sí"))

    def test_no_cancels_without_creating(self):
        self.pending = {"capability": "REGISTER_CLIENT", "fullName": "Ana López"}
        out = wr.reply_to(CHANNEL, PHONE, "Ana", "no")
        self.assertIn("no te registré", out)
        self.assertEqual(self.clients_calls, [])

    def test_single_word_name_is_not_registered(self):
        self.pending = {"capability": "REGISTER_CLIENT", "fullName": "Ana"}
        self.assertIn("apellido", wr.reply_to(CHANNEL, PHONE, "Ana", "sí"))
        self.assertEqual(self.clients_calls, [])


if __name__ == "__main__":
    unittest.main()
