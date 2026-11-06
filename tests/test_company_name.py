"""
company_name() supplies the business name for customer text, so a failed lookup
must return "" and never raise. No database: the connection is stubbed.

Run:  venv/bin/python -m unittest tests/test_company_name.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.companies as companies  # noqa: E402
import modules.reservations as reservations  # noqa: E402


def _conn(payload):
    conn = mock.Mock()
    conn.cursor.return_value.fetchone.return_value = (json.dumps(payload),)
    return conn


class CompanyNameTest(unittest.TestCase):
    def _name(self, payload):
        with mock.patch.object(companies, "connection", return_value=_conn(payload)):
            return companies.company_name({"companyId": 7})

    def test_reads_both_response_shapes(self):
        self.assertEqual(self._name({"companies": [{"name": "Tienda"}]}), "Tienda")
        self.assertEqual(self._name({"result": [{"companies": [{"name": "Tienda"}]}]}), "Tienda")

    def test_an_unknown_company_is_empty(self):
        self.assertEqual(self._name({"companies": []}), "")

    def test_a_database_failure_is_empty(self):
        with mock.patch.object(companies, "connection", side_effect=RuntimeError("down")):
            self.assertEqual(companies.company_name({"companyId": 7}), "")


class ReservationCompanyTest(unittest.TestCase):
    ROW = {"companyId": 7, "phone": "+52", "clientName": "Ana", "serviceType": "Corte",
           "reservationDate": "2026-11-06", "timeSlot": "10:00", "reservationId": 1}

    def _sms_body(self, name):
        with mock.patch.object(reservations, "company_name", return_value=name), \
             mock.patch.object(reservations, "send_sms") as sms, \
             mock.patch.object(reservations, "send_whatsapp"):
            reservations.notify_customer(self.ROW)
        return str(sms.call_args)

    def test_the_message_names_the_reservations_company(self):
        self.assertIn("Tienda", self._sms_body("Tienda"))

    def test_a_failed_lookup_falls_back(self):
        self.assertIn(reservations.FALLBACK_COMPANY_NAME, self._sms_body(""))


if __name__ == "__main__":
    unittest.main()
