"""send_client_login_code returns the matched client's name for the PIN
screen greeting -- except for the walk-in record (clientId 1)."""
import json
import unittest
from unittest import mock

from modules import client_login


def _status(client):
    return {"result": [{"error": "0", "client": client}]}


class SendClientLoginCodeGreetingTests(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(client_login, "log_workflow_step")
        self.log = patcher.start()
        self.addCleanup(patcher.stop)

    def call(self, client, reset_pin=False):
        def sp(payload):
            action = payload["clientLoginCodes"][0]["action"]
            return _status(client) if action == 3 else {"result": [{"error": "0"}]}
        with mock.patch.object(client_login, "_client_login_codes_sp", side_effect=sp), \
             mock.patch.object(client_login, "_send_sms_otp", return_value="sms"):
            response = client_login.send_client_login_code(
                {"clientLoginCodes": [{"phone": "+526621234567", "resetPin": reset_pin}]})
        return json.loads(response.body)

    def test_returning_client_gets_full_name(self):
        body = self.call({"clientId": 2242, "first_name": "Gilbertito", "last_name": "Ozuna",
                          "firstLoginCompleted": 1})
        self.assertEqual(body, {"found": True, "firstLoginCompleted": True,
                                "clientId": 2242, "firstName": "Gilbertito", "lastName": "Ozuna"})

    def test_code_sent_response_also_carries_name(self):
        body = self.call({"clientId": 2242, "first_name": "Gilbertito", "last_name": "Ozuna",
                          "firstLoginCompleted": 0})
        self.assertEqual(body["firstName"], "Gilbertito")
        self.assertEqual(body["lastName"], "Ozuna")
        self.assertEqual(body["channel"], "sms")

    def test_walk_in_record_gets_no_name(self):
        body = self.call({"clientId": 1, "first_name": "Desconocido", "last_name": "-1",
                          "firstLoginCompleted": 1})
        self.assertEqual(body, {"found": True, "firstLoginCompleted": True})

    def test_name_and_phone_are_never_logged(self):
        self.call({"clientId": 2242, "first_name": "Gilbertito", "last_name": "Ozuna",
                   "firstLoginCompleted": 0})
        logged = repr(self.log.call_args_list)
        for secret in ("Gilbertito", "Ozuna", "6621234567"):
            self.assertNotIn(secret, logged)


if __name__ == "__main__":
    unittest.main()
