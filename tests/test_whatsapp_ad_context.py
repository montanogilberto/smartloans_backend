"""
WhatsApp bot: the ad that opened the chat reaches the agent (adReferral).

Ad clicks often arrive with Meta's default greeting ("Can I learn more about
your business?"), which says nothing about the campaign — without the ad's
headline/body the agent answered as a generic info question and never ran the
demand-signal flow. Only the ad's text is sent: no ids or click ids.
No database / no agent: httpx and the state SPs are stubbed.

Run:  venv/bin/python -m unittest tests/test_whatsapp_ad_context.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.whatsappReservations as wr  # noqa: E402

CHANNEL = {"channelId": 3, "companyId": 1, "branchId": None, "phoneNumberId": "1330937783442101"}
PHONE = "+5216621234567"
REFERRAL = {"source_type": "ad", "source_id": "120200000000000001", "ctwa_clid": "secret-click-id",
            "headline": "Lockers GMO", "body": "Deja tu ropa y recógela lista", "source_url": "https://fb.me/x"}


class AdContextTest(unittest.TestCase):
    def setUp(self):
        self.sent = []

        def fake_post(url, json, timeout):
            self.sent.append(json)
            resp = mock.Mock(status_code=200)
            resp.json.return_value = {"reply": "¡Hola!", "pendingAction": None}
            return resp

        patches = [
            mock.patch.object(wr, "AGENT_URL", "https://agent.test"),
            mock.patch.object(wr.whatsappChannels, "get_state", side_effect=lambda *a: {
                "staffPaused": False, "pending": None, "lastBooked": None}),
            mock.patch.object(wr.httpx, "post", side_effect=fake_post),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def test_ad_text_reaches_the_agent_without_ids(self):
        wr.reply_to(CHANNEL, PHONE, "Karla", "Can I learn more about your business?", ad_referral=REFERRAL)
        ad = self.sent[0]["adReferral"]
        self.assertEqual(ad, {"headline": "Lockers GMO", "body": "Deja tu ropa y recógela lista",
                              "sourceType": "ad"})
        self.assertNotIn("secret-click-id", str(self.sent[0]))

    def test_no_ad_means_no_ad_context(self):
        wr.reply_to(CHANNEL, PHONE, "Ana", "hola")
        self.assertIsNone(self.sent[0]["adReferral"])


if __name__ == "__main__":
    unittest.main()
