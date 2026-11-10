"""
POST /voiceCalls/place — the virtual Secretary phones a client.

The client lookup, company name, Twilio and the DB loggers are mocked: these
tests check the guards (flag, config, walk-in, company, phone), what is sent to
Twilio, the call-token format LoanAgents verifies, and the staff-session guard.

Run:  venv/bin/python -m unittest tests/test_voice_calls.py -v
"""
import asyncio
import base64
import hashlib
import hmac
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import HTTPException  # noqa: E402

import modules.voiceCalls as vc  # noqa: E402
import security.session_tokens as st  # noqa: E402

ENV = {
    "VOICE_CALLS_ENABLED": "1", "TWILIO_ACCOUNT_SID": "ACtest", "TWILIO_AUTH_TOKEN": "auth",
    "TWILIO_VOICE_FROM": "+15550000000", "VOICE_CALL_SECRET": "s" * 32,
    "VOICE_STREAM_URL": "wss://agents.example/voice/twilio-stream",
}
CLIENT = {"clientId": 5416, "companyId": 1, "first_name": "Alison", "cellphone": "+526625235013"}


def _req(**over):
    row = {"companyId": 1, "clientId": 5416, "userId": 9}
    row.update(over)
    return {"voiceCall": [row]}


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


class PlaceCallTest(unittest.TestCase):
    def setUp(self):
        self.client = dict(CLIENT)
        twilio = mock.Mock(status_code=201)
        twilio.json.return_value = {"sid": "CA123", "status": "queued"}
        patches = {
            "env": mock.patch.dict(os.environ, ENV),
            "find": mock.patch.object(vc, "_find_client", side_effect=lambda _id: self.client),
            "name": mock.patch.object(vc, "company_name", return_value="Lavandería Sol"),
            "post": mock.patch.object(vc.httpx, "post", return_value=twilio),
            "step": mock.patch.object(vc, "log_workflow_step"),
            "integration": mock.patch.object(vc, "timed_integration"),
        }
        self.m = {k: p.start() for k, p in patches.items()}
        self.m["integration"].return_value.__enter__.return_value = mock.Mock()
        self.addCleanup(mock.patch.stopall)

    def _body(self, res):
        return json.loads(res.body)

    def test_dials_the_clients_own_phone_with_a_signed_token(self):
        res = vc.place_call(_req())
        self.assertEqual(res.status_code, 200)
        self.assertEqual(self._body(res), {"placed": True, "callSid": "CA123", "status": "queued"})
        data = self.m["post"].call_args.kwargs["data"]
        self.assertEqual((data["To"], data["From"]), ("+526625235013", "+15550000000"))
        self.assertIn('url="wss://agents.example/voice/twilio-stream"', data["Twiml"])
        token = data["Twiml"].split('name="token" value="')[1].split('"')[0]
        body, sig = token.split(".")
        expected = base64.urlsafe_b64encode(
            hmac.new(ENV["VOICE_CALL_SECRET"].encode(), body.encode(), hashlib.sha256).digest()).rstrip(b"=").decode()
        self.assertEqual(sig, expected)
        payload = json.loads(_unb64(body))
        self.assertEqual((payload["companyId"], payload["clientId"], payload["customerName"], payload["companyName"]),
                         (1, 5416, "Alison", "Lavandería Sol"))
        self.assertIsInstance(payload["exp"], int)

    def test_logs_carry_no_phone(self):
        vc.place_call(_req())
        self.assertNotIn("6625235013", str(self.m["step"].call_args_list))
        self.assertNotIn("6625235013", str(self.m["integration"].call_args_list))

    def test_off_unless_enabled(self):
        with mock.patch.dict(os.environ, {"VOICE_CALLS_ENABLED": ""}):
            res = vc.place_call(_req())
        self.assertEqual((res.status_code, self._body(res)["error"]), (503, "disabled"))
        self.m["post"].assert_not_called()

    def test_not_configured(self):
        with mock.patch.dict(os.environ, {"VOICE_STREAM_URL": "http://insecure"}):
            res = vc.place_call(_req())
        self.assertEqual(self._body(res)["error"], "not_configured")
        self.m["post"].assert_not_called()

    def test_walk_in_is_never_called(self):
        res = vc.place_call(_req(clientId=1))
        self.assertEqual(self._body(res)["error"], "walk_in")
        self.m["post"].assert_not_called()

    def test_client_of_another_company_is_not_found(self):
        self.client["companyId"] = 1008
        res = vc.place_call(_req())
        self.assertEqual((res.status_code, self._body(res)["error"]), (404, "not_found"))
        self.m["post"].assert_not_called()

    def test_no_usable_phone(self):
        for phone in ("", "123", None):
            self.client["cellphone"] = phone
            self.assertEqual(self._body(vc.place_call(_req()))["error"], "no_phone")
        self.m["post"].assert_not_called()

    def test_twilio_refusal(self):
        self.m["post"].return_value.raise_for_status.side_effect = RuntimeError("400")
        res = vc.place_call(_req())
        self.assertEqual((res.status_code, self._body(res)["error"]), (502, "call_failed"))

    def test_phone_normalization(self):
        self.assertEqual(vc.to_e164_mx("662 523 5013"), "+526625235013")
        self.assertEqual(vc.to_e164_mx("5216625235013"), "+526625235013")
        self.assertEqual(vc.to_e164_mx("526625235013"), "+526625235013")
        self.assertEqual(vc.to_e164_mx("15550000000"), "")


class StaffSessionGuardTest(unittest.TestCase):
    def setUp(self):
        self.addCleanup(mock.patch.stopall)
        mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": "j" * 40}).start()
        mock.patch("security.worker_key.WORKER_KEY", "wk").start()  # read at import time

    def _run(self, body, token=None, worker_key=None):
        request = mock.Mock()
        request.headers = {"authorization": f"Bearer {token}"} if token else {}

        async def _json():
            return body
        request.json = _json
        guard = st.require_company_staff_session("voiceCall")
        return asyncio.run(guard(request, worker_key))

    def _token(self, role="employee", company=1, user=9):
        return st.issue_session(user, company, 0, role)["accessToken"]

    def test_staff_of_the_company_passes(self):
        self.assertIsNone(self._run(_req(), self._token()))

    def test_other_company_or_user_or_role_is_forbidden(self):
        for token, body in ((self._token(company=1008), _req()), (self._token(), _req(userId=10)),
                            (self._token(role="pos"), _req()), (self._token(role="borrower"), _req())):
            with self.assertRaises(HTTPException) as ctx:
                self._run(body, token)
            self.assertEqual(ctx.exception.status_code, 403)

    def test_bad_token_is_401(self):
        with self.assertRaises(HTTPException) as ctx:
            self._run(_req(), "nope")
        self.assertEqual(ctx.exception.status_code, 401)

    def test_no_token_needs_worker_key(self):
        with self.assertRaises(HTTPException):
            self._run(_req())
        self.assertIsNone(self._run(_req(), worker_key="wk"))


if __name__ == "__main__":
    unittest.main()
