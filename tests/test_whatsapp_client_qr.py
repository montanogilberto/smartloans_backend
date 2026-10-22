"""
WhatsApp bot: "mi QR" (menu option 7) sends the customer their own client QR.

The agent proposes SEND_CLIENT_QR (no "sí", like REQUEST_HUMAN); the backend
matches the sender by phone exactly like their points (sp_whatsappCustomerRewards)
and sends the CLIENT:<id>:<name> QR the POS scanner reads, as an image uploaded
to Meta. No database / no Meta / no agent: everything external is stubbed.

Run:  venv/bin/python -m unittest tests/test_whatsapp_client_qr.py -v
"""
import io
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import segno  # noqa: E402

import modules.whatsappCloud as wc  # noqa: E402
import modules.whatsappReservations as wr  # noqa: E402

CHANNEL = {"channelId": 3, "companyId": 1, "branchId": None, "phoneNumberId": "1330937783442101"}
PHONE = "+526621234567"


def _png(value: str) -> bytes:
    buf = io.BytesIO()
    segno.make(value, error="h").save(buf, kind="png", scale=12, border=4)
    return buf.getvalue()


class ReplyToSendClientQrTest(unittest.TestCase):
    def setUp(self):
        self.lookup = {"result": [{"status": "found", "clientId": 2290, "firstName": "Denia", "balance": 7.5}]}
        self.agent_reply = "¿Te ayudo con algo más?"
        patches = [
            mock.patch.object(wr, "AGENT_URL", "https://agent.test"),
            mock.patch.object(wr.whatsappChannels, "get_state",
                              return_value={"staffPaused": False, "pending": None, "lastBooked": None}),
            mock.patch.object(wr, "_ask_agent", side_effect=lambda *a: (
                self.agent_reply, {"capability": "SEND_CLIENT_QR", "fields": {}})),
            mock.patch.object(wr, "assistant_sp", side_effect=self._sp),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.sp_calls = []

    def _sp(self, procedure, payload):
        self.sp_calls.append((procedure, payload))
        if isinstance(self.lookup, Exception):
            raise self.lookup
        return self.lookup

    def reply(self, send_image=None):
        send_image = send_image or mock.MagicMock(return_value={"messageId": "wamid.QR"})
        with mock.patch.object(wc, "send_image", send_image):
            out = wr.reply_to(CHANNEL, PHONE, "Denia", "7")
        return out, send_image

    def test_found_sends_the_qr_the_pos_scanner_reads(self):
        out, send_image = self.reply()
        self.assertEqual(out, self.agent_reply)
        self.assertEqual(self.sp_calls, [("sp_whatsappCustomerRewards",
                                          {"customerRewards": [{"companyId": 1, "phone": PHONE}]})])
        channel, to, image, caption = send_image.call_args.args
        self.assertEqual((channel, to), (CHANNEL, PHONE))
        self.assertEqual(image, _png("CLIENT:2290:Denia"))
        self.assertTrue(image.startswith(b"\x89PNG"))
        self.assertIn("caja", caption)
        self.assertEqual(send_image.call_args.kwargs["filename"], "mi-qr.png")

    def test_not_found_says_why_and_sends_nothing(self):
        self.lookup = {"result": [{"status": "not_found"}]}
        out, send_image = self.reply()
        send_image.assert_not_called()
        self.assertTrue(out.startswith(wr._QR_NOT_FOUND))
        self.assertTrue(out.endswith(self.agent_reply))

    def test_ambiguous_says_why_and_sends_nothing(self):
        self.lookup = {"result": [{"status": "ambiguous"}]}
        out, send_image = self.reply()
        send_image.assert_not_called()
        self.assertTrue(out.startswith(wr._QR_AMBIGUOUS))

    def test_lookup_or_send_failure_never_claims_a_qr(self):
        self.lookup = RuntimeError("db down")
        out, _ = self.reply()
        self.assertTrue(out.startswith(wr._QR_FAILED))

        self.lookup = {"result": [{"status": "found", "clientId": 2290, "firstName": "Denia"}]}
        out, _ = self.reply(send_image=mock.MagicMock(side_effect=RuntimeError("meta 400")))
        self.assertTrue(out.startswith(wr._QR_FAILED))

    def test_empty_agent_text_still_explains(self):
        self.agent_reply = ""
        self.lookup = {"result": [{"status": "not_found"}]}
        out, _ = self.reply()
        self.assertEqual(out, wr._QR_NOT_FOUND)

    def test_staff_paused_chat_gets_no_qr(self):
        with mock.patch.object(wr.whatsappChannels, "get_state",
                               return_value={"staffPaused": True, "pending": None, "lastBooked": None}):
            out, send_image = self.reply()
        self.assertIsNone(out)
        send_image.assert_not_called()


class SendImageTest(unittest.TestCase):
    def test_uploads_to_meta_then_sends_by_media_id(self):
        upload = mock.MagicMock(status_code=200, json=lambda: {"id": "MEDIA1"})
        sent = mock.MagicMock(status_code=200, json=lambda: {"messages": [{"id": "wamid.QR"}]})
        with mock.patch.object(wc.whatsappChannels, "access_token", return_value="tok"), \
             mock.patch.object(wc.httpx, "post", side_effect=[upload, sent]) as post:
            out = wc.send_image(CHANNEL, "+5216621234567", b"\x89PNG...", "Tu QR", filename="mi-qr.png")
        self.assertEqual(out["messageId"], "wamid.QR")
        media_call, message_call = post.call_args_list
        self.assertTrue(media_call.args[0].endswith("/1330937783442101/media"))
        self.assertEqual(media_call.kwargs["files"], {"file": ("mi-qr.png", b"\x89PNG...", "image/png")})
        self.assertEqual(media_call.kwargs["data"], {"messaging_product": "whatsapp", "type": "image/png"})
        body = message_call.kwargs["json"]
        self.assertEqual((body["to"], body["type"], body["image"]),
                         ("526621234567", "image", {"id": "MEDIA1", "caption": "Tu QR"}))

    def test_failed_upload_raises_and_sends_nothing(self):
        upload = mock.MagicMock(status_code=400, json=lambda: {"error": {"message": "bad"}})
        with mock.patch.object(wc.whatsappChannels, "access_token", return_value="tok"), \
             mock.patch.object(wc.httpx, "post", side_effect=[upload]) as post:
            with self.assertRaises(RuntimeError):
                wc.send_image(CHANNEL, PHONE, b"x", "c")
        self.assertEqual(post.call_count, 1)


if __name__ == "__main__":
    unittest.main()
