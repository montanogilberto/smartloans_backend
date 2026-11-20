"""
Micro-deposit verification is attempt-limited (RFC-018 §3.3): the SP compares
and counts, the module maps the result, fails closed when the counter isn't
deployed, and the public /bankAccounts passthrough can't set verification state.
No database: _sp is stubbed.

Run:  venv/bin/python -m unittest tests/test_bank_account_verify_attempts.py -v
"""
import asyncio
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.bankAccounts as ba  # noqa: E402

ROW = {"bankAccountId": 7, "clientId": 3371, "isVerified": False, "verificationCents": 42}
REQ = {"clientId": 3371, "companyId": 1, "bankAccountId": 7, "amountCents": 42}


def _body(response):
    return json.loads(response.body)


class VerifyAttemptsTest(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.attempt_result = {}

        def fake_sp(proc, payload):
            req = payload["bankAccounts"][0]
            self.calls.append((proc, req))
            if proc == "sp_bankAccounts_one":
                return dict(ROW)
            if proc == "sp_bankAccounts" and req.get("action") == 4:
                return self.attempt_result
            if proc == "sp_bankAccounts" and req.get("action") == 2:
                return {"bankAccountId": 7, "isVerified": True}
            return {}

        patcher = mock.patch.object(ba, "_sp", side_effect=fake_sp)
        patcher.start()
        self.addCleanup(patcher.stop)

    def verify(self, **overrides):
        return asyncio.run(ba.verify_bank_account({**REQ, **overrides}))

    def actions(self):
        return [req.get("action") for proc, req in self.calls if proc == "sp_bankAccounts"]

    def test_match_verifies(self):
        self.attempt_result = {"matched": True, "locked": False, "attempts": 0, "attemptsRemaining": 3}
        r = self.verify()
        self.assertEqual(r.status_code, 200)
        self.assertTrue(_body(r)["verified"])
        self.assertEqual(self.actions(), [4, 2])

    def test_attempt_carries_amount_and_limit(self):
        self.attempt_result = {"matched": True}
        self.verify()
        req = next(req for proc, req in self.calls if req.get("action") == 4)
        self.assertEqual(req["amountCents"], 42)
        self.assertEqual(req["clientId"], 3371)
        self.assertEqual(req["maxAttempts"], ba.MAX_VERIFICATION_ATTEMPTS)

    def test_wrong_amount_reports_remaining_and_does_not_verify(self):
        self.attempt_result = {"matched": False, "locked": False, "attempts": 1, "attemptsRemaining": 2}
        r = self.verify(amountCents=11)
        self.assertEqual(r.status_code, 400)
        body = _body(r)
        self.assertFalse(body["verified"])
        self.assertEqual(body["attemptsRemaining"], 2)
        self.assertIn("Te quedan 2 intentos", body["error"])
        self.assertNotIn(2, self.actions())

    def test_last_attempt_singular(self):
        self.attempt_result = {"matched": False, "locked": False, "attempts": 2, "attemptsRemaining": 1}
        self.assertIn("Te quedan 1 intento.", _body(self.verify(amountCents=11))["error"])

    def test_locked_is_423_and_does_not_verify(self):
        self.attempt_result = {"matched": False, "locked": True, "attempts": 3, "attemptsRemaining": 0}
        r = self.verify()
        self.assertEqual(r.status_code, 423)
        self.assertTrue(_body(r)["locked"])
        self.assertNotIn(2, self.actions())

    def test_fails_closed_when_counter_not_deployed(self):
        for result in ({}, {"error": "Invalid action"}, None):
            self.calls.clear()
            self.attempt_result = result
            r = self.verify()
            self.assertEqual(r.status_code, 503)
            self.assertFalse(_body(r)["verified"])
            self.assertNotIn(2, self.actions())

    def test_malformed_amount_costs_no_attempt(self):
        for bad in ("abc", 0, 100, -5, None):
            self.calls.clear()
            r = self.verify(amountCents=bad)
            self.assertEqual(r.status_code, 400)
            self.assertNotIn(4, self.actions())

    def test_other_client_gets_404_without_attempt(self):
        r = self.verify(clientId=999)
        self.assertEqual(r.status_code, 404)
        self.assertNotIn(4, self.actions())


class PassthroughGuardTest(unittest.TestCase):
    def test_rejects_verification_fields(self):
        with mock.patch.object(ba, "_sp") as sp:
            for req in ({"action": 2, "bankAccountId": 7, "companyId": 1, "isVerified": True},
                        {"action": 2, "bankAccountId": 7, "companyId": 1, "verificationAttempts": 0},
                        {"action": 1, "clientId": 1, "companyId": 1, "verificationCents": 5},
                        {"action": 4, "bankAccountId": 7, "clientId": 1, "amountCents": 42}):
                r = ba.bank_accounts_sp({"bankAccounts": [req]})
                self.assertEqual(r.status_code, 403, req)
            sp.assert_not_called()

    def test_allows_other_updates(self):
        with mock.patch.object(ba, "_sp", return_value={"bankAccountId": 7}) as sp:
            r = ba.bank_accounts_sp({"bankAccounts": [{"action": 2, "bankAccountId": 7,
                                                       "companyId": 1, "isDefault": True}]})
            self.assertEqual(r.status_code, 200)
            sp.assert_called_once()


class ListAnnotationTest(unittest.TestCase):
    def test_lock_and_remaining_from_counter(self):
        with mock.patch.object(ba, "is_mock", return_value=False):
            a = ba._annotate_verification({"bankAccountId": 7, "isVerified": False, "verificationAttempts": 1})
            self.assertEqual(a["attemptsRemaining"], ba.MAX_VERIFICATION_ATTEMPTS - 1)
            self.assertFalse(a["verificationLocked"])
            locked = ba._annotate_verification({"bankAccountId": 7, "isVerified": False,
                                                "verificationAttempts": ba.MAX_VERIFICATION_ATTEMPTS})
            self.assertTrue(locked["verificationLocked"])
            self.assertEqual(locked["attemptsRemaining"], 0)

    def test_locked_account_gets_no_mock_code(self):
        with mock.patch.object(ba, "is_mock", return_value=True), \
             mock.patch.object(ba, "_sp", return_value={"verificationCents": 42}) as sp:
            a = ba._annotate_verification({"bankAccountId": 7, "isVerified": False,
                                           "verificationAttempts": ba.MAX_VERIFICATION_ATTEMPTS})
            self.assertNotIn("mockVerificationCents", a)
            sp.assert_not_called()

    def test_no_counter_before_migration(self):
        with mock.patch.object(ba, "is_mock", return_value=False):
            a = ba._annotate_verification({"bankAccountId": 7, "isVerified": False})
            self.assertNotIn("verificationLocked", a)
            self.assertFalse(a["microDepositSent"])


if __name__ == "__main__":
    unittest.main()
