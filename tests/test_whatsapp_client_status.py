"""
WhatsApp bot: every message tells the agent whether the sender is already a
client of the company (by phone, like points/QR), so the agent's route picks
the client or the prospect instructions — the model never decides it.

Run:  venv/bin/python -m unittest tests/test_whatsapp_client_status.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.whatsappReservations as wr  # noqa: E402

CHANNEL = {"channelId": 3, "companyId": 1, "branchId": 1}
PHONE = "+5216621234567"


class ClientStatusTest(unittest.TestCase):
    def _status(self, lookup):
        with mock.patch.object(wr, "assistant_sp", side_effect=lookup) as sp:
            out = wr._client_status(1, PHONE)
        return out, sp

    def test_found_sends_only_status_and_first_name(self):
        out, sp = self._status(lambda *a: {"result": [{"status": "found", "clientId": 9, "firstName": "Ana",
                                                         "balance": 40, "redeemable": []}]})
        self.assertEqual(out, {"status": "found", "firstName": "Ana"})
        self.assertEqual(sp.call_args.args[1], {"customerRewards": [{"companyId": 1, "phone": PHONE}]})

    def test_not_found_and_ambiguous_pass_through(self):
        for status in ("not_found", "ambiguous"):
            self.assertEqual(self._status(lambda *a, s=status: {"result": [{"status": s}]})[0], {"status": status})

    def test_failure_or_odd_answer_is_unavailable(self):
        def boom(*a):
            raise RuntimeError("db down")
        self.assertEqual(self._status(boom)[0], {"status": "unavailable"})
        self.assertEqual(self._status(lambda *a: {"result": []})[0], {"status": "unavailable"})

    def test_reply_to_sends_the_status_to_the_agent(self):
        resp = mock.MagicMock()
        resp.json.return_value = {"reply": "hola", "pendingAction": None}
        with mock.patch.object(wr, "AGENT_URL", "https://agent.test"), \
                mock.patch.object(wr.whatsappChannels, "get_state",
                                  return_value={"staffPaused": False, "pending": None, "lastBooked": None}), \
                mock.patch.object(wr, "assistant_sp",
                                  return_value={"result": [{"status": "found", "firstName": "Ana"}]}), \
                mock.patch.object(wr.httpx, "post", return_value=resp) as post:
            self.assertEqual(wr.reply_to(CHANNEL, PHONE, "Anita", "hola"), "hola")
        self.assertEqual(post.call_args.kwargs["json"]["client"], {"status": "found", "firstName": "Ana"})


if __name__ == "__main__":
    unittest.main()
