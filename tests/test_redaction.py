"""
Log redaction — secrets masked, ordinary keys kept.

Run:  venv/bin/python -m unittest tests/test_redaction.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from observability import integrations  # noqa: E402
from observability.redaction import redact  # noqa: E402


class RedactionTest(unittest.TestCase):
    def test_short_keys_do_not_mask_ordinary_keys(self):
        # "pan" is inside companyId, "pin" inside shipping, "auth" inside author.
        out = json.loads(redact({"companyId": 1, "companyName": "X", "shipping": 2, "author": "a"}))
        self.assertEqual(out, {"companyId": 1, "companyName": "X", "shipping": 2, "author": "a"})

    def test_secrets_still_masked(self):
        keys = ["pan", "cardNumber", "pin", "userPin", "otp", "smsOtp", "password",
                "apiKey", "authorization", "auth", "accessToken", "rfc", "clientRfc", "curp"]
        out = json.loads(redact({k: "secret" for k in keys}))
        self.assertEqual(out, {k: "***" for k in keys})

    def test_nested_values_masked(self):
        out = json.loads(redact({"payment": {"cardNumber": "4111", "companyId": 3}}))
        self.assertEqual(out, {"payment": {"cardNumber": "***", "companyId": 3}})


class IntegrationCompanyTest(unittest.TestCase):
    def test_explicit_company_id_reaches_the_log(self):
        with mock.patch.object(integrations, "log_integration") as log:
            with integrations.timed_integration("svc", "op", request={}, company_id=7):
                pass
        self.assertEqual(log.call_args.kwargs["company_id"], 7)

    def test_company_id_defaults_to_none(self):
        with mock.patch.object(integrations, "log_integration") as log:
            with integrations.timed_integration("svc", "op"):
                pass
        self.assertIsNone(log.call_args.kwargs["company_id"])


if __name__ == "__main__":
    unittest.main()
