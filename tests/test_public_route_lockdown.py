"""
Public-route lockdown: generic table routes are gone, passwords never reach a
response, internal routes need X-Worker-Key, send routes are rate-limited.

Nothing here reaches the database or a provider: the modules are mocked.

Run:  venv/bin/python -m unittest tests/test_public_route_lockdown.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.users as users  # noqa: E402
import routes_.arcadeStore as arcade_routes  # noqa: E402
import routes_.automatedPayments as payments_routes  # noqa: E402
import routes_.client_login as client_login_routes  # noqa: E402
import routes_.notificationDispatch as dispatch_routes  # noqa: E402
import routes_.onboardingReminders as onboarding_routes  # noqa: E402
import routes_.registrationReminders as registration_routes  # noqa: E402
import routes_.reservations as reservations_routes  # noqa: E402
import routes_.tickets as tickets_routes  # noqa: E402
import routes_.users as users_routes  # noqa: E402
import routes_.walletBalance as wallet_routes  # noqa: E402
import routes_.whatsappCloud as whatsapp_cloud_routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402
from security import rate_limit  # noqa: E402
from security.rate_limit import RateLimitExceeded, rate_limit_handler  # noqa: E402

app = FastAPI()
app.add_exception_handler(RateLimitExceeded, rate_limit_handler)
for module in (arcade_routes, payments_routes, client_login_routes, dispatch_routes, onboarding_routes,
               registration_routes, reservations_routes, tickets_routes, users_routes, wallet_routes,
               whatsapp_cloud_routes):
    app.include_router(module.router)
client = TestClient(app)

WORKER_ROUTES = (
    "/wallet/credit", "/wallet/debit", "/wallet/reserve", "/wallet/release",
    "/automated-payments/charge-due", "/arcade/speiConfirm", "/reservations/migrate",
    "/whatsapp/cloud/migrate", "/onboarding-reminders/check", "/registration-reminders/check",
)


class FakeCursor:
    def __init__(self, payload):
        self.payload = payload

    def execute(self, *_):
        pass

    def fetchone(self):
        return (json.dumps(self.payload),)

    def fetchall(self):
        return [(json.dumps(self.payload),)]

    def close(self):
        pass


class FakeConnection:
    def __init__(self, payload):
        self.payload = payload

    def cursor(self):
        return FakeCursor(self.payload)

    def close(self):
        pass


class SelectRoutesTest(unittest.TestCase):
    def test_main_does_not_register_them(self):
        with open(os.path.join(os.path.dirname(__file__), "..", "main.py"), encoding="utf-8") as f:
            self.assertNotIn("utils.router", f.read())

    def test_route_module_is_gone(self):
        root = os.path.join(os.path.dirname(__file__), "..")
        self.assertFalse(os.path.exists(os.path.join(root, "routes_", "utils.py")))


class PasswordNeverReturnedTest(unittest.TestCase):
    PAYLOAD = {"users": [{"userId": 1, "name": "Ana", "password": "secreto"}]}

    def check(self, call):
        with mock.patch.object(users, "connection", return_value=FakeConnection(self.PAYLOAD)):
            body = json.loads(call().body)
        self.assertEqual(body["users"][0]["name"], "Ana")
        self.assertNotIn("password", body["users"][0])

    def test_one_users(self):
        self.check(lambda: users.one_users_sp({"users": [{"userId": 1}]}))

    def test_one_users_email(self):
        self.check(lambda: users.one_users_email_sp({"users": [{"email": "a@b.mx"}]}))

    def test_all_users(self):
        self.check(users.all_users_sp)

    def test_nested_and_any_case(self):
        cleaned = users._without_password({"a": [{"Password": "x", "keep": 1}]})
        self.assertEqual(cleaned, {"a": [{"keep": 1}]})


class WorkerKeyTest(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(worker_key, "WORKER_KEY", "right-key")
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_refused_without_the_key(self):
        for path in WORKER_ROUTES:
            with self.subTest(path=path):
                self.assertEqual(client.post(path, json={}).status_code, 403)

    def test_refused_with_a_wrong_key(self):
        for path in WORKER_ROUTES:
            with self.subTest(path=path):
                response = client.post(path, json={}, headers={"X-Worker-Key": "wrong"})
                self.assertEqual(response.status_code, 403)

    def test_handler_runs_with_the_key(self):
        with mock.patch.object(wallet_routes, "credit_wallet",
                               new=mock.AsyncMock(return_value=JSONResponse({"wallet": {}}))) as handler:
            response = client.post("/wallet/credit", json={"clientId": 1},
                                   headers={"X-Worker-Key": "right-key"})
        self.assertEqual(response.status_code, 200)
        handler.assert_awaited_once()


class RateLimitTest(unittest.TestCase):
    def setUp(self):
        rate_limit.reset()
        self.addCleanup(rate_limit.reset)
        patcher = mock.patch.object(users_routes, "send_verification_code",
                                    return_value=JSONResponse({"message": "ok"}))
        self.sender = patcher.start()
        self.addCleanup(patcher.stop)

    def send(self, target, ip="1.1.1.1"):
        return client.post("/send_verification_code", json={"target": target},
                           headers={"X-Forwarded-For": ip})

    def test_stops_after_the_target_limit_and_does_not_send(self):
        for _ in range(5):
            self.assertEqual(self.send("6621234567").status_code, 200)
        response = self.send("6621234567")
        self.assertEqual(response.status_code, 429)
        self.assertEqual(self.sender.call_count, 5)
        self.assertEqual(response.json()["error"], rate_limit.MESSAGE)
        self.assertGreater(int(response.headers["Retry-After"]), 0)

    def test_same_phone_written_differently_counts_once(self):
        for target in ("6621234567", "+52 662 123 4567", "+526621234567", "662-123-4567", "(662) 1234567"):
            self.assertEqual(self.send(target).status_code, 200)
        self.assertEqual(self.send("526621234567").status_code, 429)

    def test_otp_routes_share_the_target_counter(self):
        for _ in range(5):
            self.send("6621234567")
        response = client.post("/send_client_login_code",
                               json={"clientLoginCodes": [{"phone": "+526621234567"}]},
                               headers={"X-Forwarded-For": "2.2.2.2"})
        self.assertEqual(response.status_code, 429)

    def test_other_targets_are_not_affected(self):
        for _ in range(6):
            self.send("6621234567")
        self.assertEqual(self.send("6629999999").status_code, 200)

    def test_ip_limit_stops_a_caller_rotating_targets(self):
        for n in range(30):
            self.assertEqual(self.send(f"66200000{n:02d}").status_code, 200)
        self.assertEqual(self.send("6620000099").status_code, 429)

    def test_spoofed_forwarded_entries_do_not_change_the_ip(self):
        for n in range(30):
            self.send(f"66200000{n:02d}", ip=f"9.9.9.{n}, 1.1.1.1:5000")
        self.assertEqual(self.send("6620000099", ip="8.8.8.8, 1.1.1.1:6000").status_code, 429)

    def test_ticket_limit_is_per_phone(self):
        with mock.patch.object(tickets_routes, "send_ticket_sms", return_value={"sent": True}):
            for _ in range(20):
                response = client.post("/api/tickets/T1/send-sms", json={"phone": "6621234567"})
                self.assertEqual(response.status_code, 200)
            response = client.post("/api/tickets/T1/send-sms", json={"phone": "6621234567"})
        self.assertEqual(response.status_code, 429)


class ClientIpTest(unittest.TestCase):
    def ip(self, forwarded):
        return rate_limit.client_ip(mock.Mock(headers={"x-forwarded-for": forwarded}, client=None))

    def test_formats(self):
        self.assertEqual(self.ip("1.2.3.4:5678"), "1.2.3.4")
        self.assertEqual(self.ip("9.9.9.9, 1.2.3.4:5678"), "1.2.3.4")
        self.assertEqual(self.ip("[2001:db8::1]:5678"), "2001:db8::1")
        self.assertEqual(self.ip("2001:db8::1"), "2001:db8::1")
        self.assertEqual(self.ip(""), "unknown")


class NoSecretsInLogsTest(unittest.TestCase):
    def test_otp_is_not_logged(self):
        with mock.patch.object(users, "_send_email_otp"), \
                mock.patch.object(users, "workflow_step"), mock.patch.object(users, "timed_integration"), \
                self.assertLogs("users", level="INFO") as logs:
            users.send_verification_code({"target": "ana@example.mx", "method": "email"})
            code = users._verification_codes["ana@example.mx"]["code"]
            users.verify_code({"target": "ana@example.mx", "code": "000000"})
        text = "\n".join(logs.output)
        self.assertNotIn(code, text)
        self.assertNotIn("ana@example.mx", text)

    def test_password_is_not_logged(self):
        cursor = mock.Mock()
        cursor.fetchone.return_value = ("1", "ok", "")
        conn = mock.Mock()
        conn.cursor.return_value = cursor
        with mock.patch.object(users, "connection", return_value=conn), \
                self.assertLogs("users", level="INFO") as logs:
            users._users_sp_raw({"users": [{"action": 2, "user_id": 1, "password": "pin-1234"}]})
        self.assertNotIn("pin-1234", "\n".join(logs.output))


if __name__ == "__main__":
    unittest.main()
