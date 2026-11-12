"""
WhatsApp webhook: a shared location pin reaches the agent as its place name /
address only; the coordinates stay in the backend (attached to the demand
signal by whatsappReservations, never sent to the model).

Run:  venv/bin/python -m unittest tests/test_whatsapp_location_pin.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.whatsappCloud as wc  # noqa: E402
import modules.whatsappReservations as wr  # noqa: E402

PIN = {"latitude": 29.089, "longitude": -110.961, "name": "Plaza Pitic", "address": "Blvd. Kino 123"}


def _payload(msg):
    return {"entry": [{"changes": [{"field": "messages", "value": {
        "metadata": {"phone_number_id": "1"}, "contacts": [{"wa_id": "5216621234567", "profile": {"name": "Ana"}}],
        "messages": [msg]}}]}]}


class LocationPinTest(unittest.TestCase):
    def test_extract_keeps_pin_and_labels_text(self):
        out = wc._extract_inbound(_payload({"from": "5216621234567", "id": "wamid.1", "type": "location",
                                            "location": PIN}))[0]
        self.assertEqual(out["text"], "[ubicación compartida] Plaza Pitic, Blvd. Kino 123")
        self.assertEqual(out["location"], PIN)

    def test_text_message_has_no_location(self):
        out = wc._extract_inbound(_payload({"from": "5216621234567", "id": "wamid.2", "type": "text",
                                            "text": {"body": "hola"}}))[0]
        self.assertIsNone(out["location"])

    def test_agent_gets_place_but_never_coordinates(self):
        resp = mock.MagicMock()
        resp.json.return_value = {"reply": "ok", "pendingAction": None}
        with mock.patch.object(wr, "AGENT_URL", "https://agent.test"), \
                mock.patch.object(wr.httpx, "post", return_value=resp) as post:
            wr._ask_agent({"channelId": 3, "companyId": 1}, "+5216621234567", "Ana", "x", None, None, PIN)
        body = post.call_args.kwargs["json"]
        self.assertEqual(body["sharedLocation"], {"name": "Plaza Pitic", "address": "Blvd. Kino 123"})
        self.assertNotIn("29.089", str(body))


if __name__ == "__main__":
    unittest.main()
