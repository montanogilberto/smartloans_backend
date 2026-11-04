"""
Session tokens: issuing at login, renewal, the set-PIN proof and /registerDevice.

Nothing here reaches the database or a provider: the SP helpers are mocked.

Run:  venv/bin/python -m unittest tests/test_session_tokens.py -v
"""
import json
import os
import sys
import time
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import jwt  # noqa: E402
from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.client_login as client_login  # noqa: E402
import modules.login as login_module  # noqa: E402
import modules.sessions as sessions  # noqa: E402
import routes_.pushNotification as push_routes  # noqa: E402
import routes_.sessionAuth as session_routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402
from security import rate_limit, session_tokens  # noqa: E402

SECRET = "s" * 40

app = FastAPI()
app.include_router(session_routes.router)
app.include_router(push_routes.router)
client = TestClient(app)


class WithSecret(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": SECRET})
        patcher.start()
        self.addCleanup(patcher.stop)
        rate_limit.reset()


class TokenTest(WithSecret):
    def test_session_carries_the_identity(self):
        session = session_tokens.issue_session("7", "1008", "21", "lender")
        claims = session_tokens.decode(session["accessToken"], "access")
        self.assertEqual(claims["sub"], "7")
        self.assertEqual(claims["clientId"], 21)
        self.assertEqual(claims["companies"], [{"companyId": 1008, "role": "lender"}])

    def test_one_kind_of_token_never_works_as_another(self):
        session = session_tokens.issue_session(7, 1, 2, "pos")
        pin = session_tokens.issue_set_pin_token(7)
        self.assertIsNone(session_tokens.decode(session["accessToken"], "refresh"))
        self.assertIsNone(session_tokens.decode(session["refreshToken"], "access"))
        self.assertIsNone(session_tokens.decode(pin, "access"))
        self.assertIsNone(session_tokens.decode(session["accessToken"], "set_pin"))

    def test_expired_token_is_rejected(self):
        now = int(time.time())
        token = jwt.encode({"sub": "7", "typ": "access", "iss": "smartloans", "iat": now - 100, "exp": now - 50},
                           SECRET, algorithm="HS256")
        self.assertIsNone(session_tokens.decode(token, "access"))

    def test_token_signed_with_another_secret_is_rejected(self):
        now = int(time.time())
        token = jwt.encode({"sub": "7", "typ": "access", "iss": "smartloans", "iat": now, "exp": now + 50},
                           "x" * 40, algorithm="HS256")
        self.assertIsNone(session_tokens.decode(token, "access"))

    def test_unsigned_token_is_rejected(self):
        now = int(time.time())
        token = jwt.encode({"sub": "7", "typ": "access", "iss": "smartloans", "iat": now, "exp": now + 50},
                           None, algorithm="none")
        self.assertIsNone(session_tokens.decode(token, "access"))

    def test_nothing_is_issued_or_accepted_without_a_secret(self):
        token = session_tokens.issue_session(7)["accessToken"]
        with mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": "short"}):
            self.assertIsNone(session_tokens.issue_session(7))
            self.assertIsNone(session_tokens.decode(token, "access"))


class LoginIssuesSessionTest(WithSecret):
    def run_login(self, row):
        cursor = mock.Mock()
        cursor.fetchone.return_value = (json.dumps({"result": [row]}),)
        conn = mock.Mock()
        conn.cursor.return_value = cursor
        with mock.patch.object(login_module, "connection", return_value=conn), \
                mock.patch.object(login_module, "log_application"):
            return json.loads(login_module.login_sp({"logins": [{"username": "a", "password": "b"}]}).body)

    def test_valid_login(self):
        body = self.run_login({"userId": "7", "companyId": "1", "clientId": "0", "roleCode": "admin",
                               "msg": "User Valid", "error": ""})
        claims = session_tokens.decode(body["result"][0]["session"]["accessToken"], "access")
        self.assertEqual(claims["sub"], "7")

    def test_failed_login_gets_no_session(self):
        body = self.run_login({"userId": "", "companyId": "", "msg": "User Invalid", "error": "1"})
        self.assertNotIn("session", body["result"][0])

    def test_login_still_works_without_a_secret(self):
        with mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": ""}):
            body = self.run_login({"userId": "7", "companyId": "1", "msg": "User Valid", "error": ""})
        self.assertEqual(body["result"][0]["userId"], "7")
        self.assertNotIn("session", body["result"][0])


class ClientLoginTest(WithSecret):
    CLIENT = {"clientId": 21, "companyId": 1, "first_name": "Ana", "existingUserId": 7,
              "existingRoleCode": "pos", "hasCompanyRole": 1}

    def test_verified_code_gives_a_session_and_a_pin_token(self):
        with mock.patch.object(client_login, "_client_login_codes_sp",
                               return_value={"result": [{"client": self.CLIENT}]}), \
                mock.patch.object(client_login, "_users_sp_raw", return_value={}), \
                mock.patch.object(client_login, "log_workflow_step"):
            body = json.loads(client_login.verify_client_login_code(
                {"clientLoginCodes": [{"phone": "6621234567", "code": "123456"}]}).body)
        self.assertEqual(session_tokens.decode(body["pinToken"], "set_pin")["sub"], "7")
        self.assertEqual(session_tokens.decode(body["session"]["accessToken"], "access")["sub"], "7")

    def test_wrong_code_gives_neither(self):
        with mock.patch.object(client_login, "_client_login_codes_sp",
                               return_value={"result": [{"error": "1", "msg": "Código incorrecto"}]}):
            body = json.loads(client_login.verify_client_login_code(
                {"clientLoginCodes": [{"phone": "6621234567", "code": "000000"}]}).body)
        self.assertNotIn("session", body)
        self.assertNotIn("pinToken", body)

    def test_pin_login_gives_a_session_but_no_pin_token(self):
        client_row = {**self.CLIENT, "userId": 7}
        with mock.patch.object(client_login, "_client_login_codes_sp",
                               return_value={"result": [{"client": client_row}]}), \
                mock.patch.object(client_login, "log_workflow_step"):
            body = json.loads(client_login.verify_client_password(
                {"clientPasswordLogin": [{"phone": "6621234567", "password": "1234"}]}).body)
        self.assertIn("session", body)
        self.assertNotIn("pinToken", body)


class SetPinTest(WithSecret):
    def set_pin(self, user_id=7, **extra):
        users_sp = mock.patch.object(client_login, "_users_sp_raw", return_value={})
        with users_sp as sp, mock.patch.object(client_login, "log_workflow_step"):
            row = {"userId": user_id, "password": "1234", **extra}
            response = client_login.set_client_password({"setClientPassword": [row]})
        return response.status_code, sp.called

    def test_flag_on_refuses_a_missing_token(self):
        with mock.patch.dict(os.environ, {"AUTH_REQUIRE_PIN_TOKEN": "1"}):
            self.assertEqual(self.set_pin(), (401, False))

    def test_flag_on_accepts_the_right_token(self):
        with mock.patch.dict(os.environ, {"AUTH_REQUIRE_PIN_TOKEN": "1"}):
            self.assertEqual(self.set_pin(pinToken=session_tokens.issue_set_pin_token(7)), (200, True))

    def test_another_users_token_is_refused_even_with_the_flag_off(self):
        self.assertEqual(self.set_pin(pinToken=session_tokens.issue_set_pin_token(8)), (401, False))

    def test_session_token_is_not_a_pin_proof(self):
        access = session_tokens.issue_session(7)["accessToken"]
        self.assertEqual(self.set_pin(pinToken=access), (401, False))

    def test_flag_off_keeps_old_apps_working(self):
        self.assertEqual(self.set_pin(), (200, True))


class RefreshTest(WithSecret):
    def refresh(self, token, user=None, fails=False):
        lookup = mock.patch.object(sessions, "_user_row",
                                   side_effect=RuntimeError("db down") if fails else None, return_value=user)
        with lookup:
            return client.post("/auth/refresh", json={"refreshToken": token})

    def test_renews_an_active_user(self):
        token = session_tokens.issue_session(7, 1, 2, "pos")["refreshToken"]
        response = self.refresh(token, {"active": "1"})
        self.assertEqual(response.status_code, 200)
        claims = session_tokens.decode(response.json()["accessToken"], "access")
        self.assertEqual(claims["companies"], [{"companyId": 1, "role": "pos"}])

    def test_deactivated_or_deleted_user_is_refused(self):
        token = session_tokens.issue_session(7)["refreshToken"]
        self.assertEqual(self.refresh(token, {"active": "0"}).status_code, 401)
        self.assertEqual(self.refresh(token, None).status_code, 401)

    def test_access_token_cannot_refresh(self):
        token = session_tokens.issue_session(7)["accessToken"]
        self.assertEqual(self.refresh(token, {"active": "1"}).status_code, 401)

    def test_database_failure_does_not_end_the_session(self):
        token = session_tokens.issue_session(7)["refreshToken"]
        self.assertEqual(self.refresh(token, fails=True).status_code, 503)


class RegisterDeviceTest(WithSecret):
    def setUp(self):
        super().setUp()
        for patcher in (mock.patch.object(worker_key, "WORKER_KEY", "right-key"),
                        mock.patch.object(push_routes, "register_device_sp",
                                          new=mock.AsyncMock(return_value=JSONResponse({"status": "ok"})))):
            patcher.start()
            self.addCleanup(patcher.stop)

    def post(self, headers, user_id=7):
        return client.post("/registerDevice", json={"userId": user_id, "token": "t", "platform": "ios"},
                           headers=headers)

    def bearer(self, token):
        return {"Authorization": f"Bearer {token}"}

    def test_session_for_the_same_user(self):
        token = session_tokens.issue_session(7)["accessToken"]
        self.assertEqual(self.post(self.bearer(token)).status_code, 200)

    def test_session_cannot_register_for_another_user(self):
        token = session_tokens.issue_session(7)["accessToken"]
        self.assertEqual(self.post(self.bearer(token), user_id=8).status_code, 403)

    def test_bad_token_asks_the_app_to_refresh(self):
        self.assertEqual(self.post(self.bearer("nonsense")).status_code, 401)

    def test_old_apps_with_the_worker_key(self):
        self.assertEqual(self.post({"X-Worker-Key": "right-key"}).status_code, 200)

    def test_nothing_is_refused(self):
        self.assertEqual(self.post({}).status_code, 403)


class MinVersionTest(unittest.TestCase):
    def test_reads_the_settings(self):
        with mock.patch.dict(os.environ, {"MIN_NATIVE_BUILD_IOS": "12", "MIN_NATIVE_BUILD_ANDROID": "x"}):
            self.assertEqual(client.get("/app/minVersion").json(), {"ios": 12, "android": 0})


if __name__ == "__main__":
    unittest.main()
