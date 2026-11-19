"""RFC-013: the client login code has 4 digits, says how long it is, and goes
push (app) -> WhatsApp -> SMS unless the client picked a channel."""
import json
import unittest
from unittest import mock

from modules import client_login


def _status(client):
    return {"result": [{"error": "0", "client": client}]}


CLIENT = {"clientId": 2242, "first_name": "Ana", "last_name": "Ruiz", "companyName": "Lavandería GMO",
          "existingUserId": 77, "firstLoginCompleted": 0}


class ClientLoginCodeDeliveryTests(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(client_login, "log_workflow_step")
        patcher.start()
        self.addCleanup(patcher.stop)
        self.stored = []

    def call(self, channel=None, client=CLIENT, push_device=True, push_sent=True, insert_result=None):
        def sp(payload):
            row = payload["clientLoginCodes"][0]
            if row["action"] == 3:
                return _status(client)
            self.stored.append(row)
            return insert_result or {"result": [{"error": "0"}]}

        async def has_device(_user_id):
            return {"registered": push_device}

        async def push(*_args, **_kwargs):
            return {"sent": push_sent}

        body = {"phone": "+526621234567"}
        if channel is not None:
            body["channel"] = channel
        with mock.patch.object(client_login, "_client_login_codes_sp", side_effect=sp), \
             mock.patch.object(client_login, "has_push_device", side_effect=has_device), \
             mock.patch.object(client_login, "send_azure_push", side_effect=push) as push_mock, \
             mock.patch.object(client_login, "_send_sms_otp", side_effect=lambda *a, **k:
                               "whatsapp" if k.get("via_whatsapp") else "sms") as otp_mock:
            response = client_login.send_client_login_code({"clientLoginCodes": [body]})
        return response, json.loads(response.body), push_mock, otp_mock

    def test_code_has_four_digits_and_length_is_returned(self):
        _, body, _, _ = self.call()
        code = self.stored[0]["code"]
        self.assertEqual(len(code), 4)
        self.assertTrue(code.isdigit())
        self.assertEqual(body["codeLength"], 4)

    def test_auto_goes_to_the_app_when_a_device_is_registered(self):
        _, body, push_mock, otp_mock = self.call()
        self.assertEqual(body["channel"], "push")
        self.assertEqual(push_mock.call_args.kwargs["target_user_id"], 77)
        otp_mock.assert_not_called()

    def test_auto_without_device_goes_to_whatsapp(self):
        _, body, push_mock, otp_mock = self.call(push_device=False)
        self.assertEqual(body["channel"], "whatsapp")
        push_mock.assert_not_called()
        self.assertTrue(otp_mock.call_args.kwargs["via_whatsapp"])
        self.assertEqual(otp_mock.call_args.kwargs["expires_minutes"], 5)

    def test_auto_when_the_hub_refuses_goes_to_whatsapp(self):
        _, body, _, _ = self.call(push_sent=False)
        self.assertEqual(body["channel"], "whatsapp")

    def test_auto_without_app_account_skips_push(self):
        _, body, push_mock, _ = self.call(client={**CLIENT, "existingUserId": None})
        self.assertEqual(body["channel"], "whatsapp")
        push_mock.assert_not_called()

    def test_explicit_sms_is_respected(self):
        # Also what apps released before "auto" send on every request.
        _, body, push_mock, otp_mock = self.call(channel="sms")
        self.assertEqual(body["channel"], "sms")
        push_mock.assert_not_called()
        self.assertFalse(otp_mock.call_args.kwargs["via_whatsapp"])

    def test_explicit_whatsapp_skips_push(self):
        _, body, push_mock, _ = self.call(channel="whatsapp")
        self.assertEqual(body["channel"], "whatsapp")
        push_mock.assert_not_called()

    def test_daily_limit_is_a_429_with_the_message(self):
        limit = {"result": [{"error": "1", "value": "DAILY_LIMIT", "msg": "Alcanzaste el límite de códigos por hoy."}]}
        response, body, _, otp_mock = self.call(insert_result=limit)
        self.assertEqual(response.status_code, 429)
        self.assertEqual(body["error"], "Alcanzaste el límite de códigos por hoy.")
        otp_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
