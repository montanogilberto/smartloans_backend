"""
Step 8 — /journalEntries/balance-sheet wrapper: passes the SP's JSON through
untouched (no math in Python) and maps errors to 400.

Run:  venv/bin/python -m unittest tests/test_balance_sheet_endpoint.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.journalEntries as je  # noqa: E402

SAMPLE = {
    "companyId": 1, "asOfDate": "2026-09-30",
    "assets": {"current": [{"code": "1101", "name": "Caja", "balance": 1090.0}], "nonCurrent": [], "total": 1090.0},
    "liabilities": {"current": [], "nonCurrent": [], "total": 0.0},
    "equity": {"accounts": [{"code": "3105", "name": "Capital social", "balance": 1000.0}],
               "priorYearsResult": 0.0, "currentYearResult": 90.0, "total": 1090.0},
    "totalLiabilitiesAndEquity": 1090.0, "balanced": True,
}


class BalanceSheetEndpointTest(unittest.TestCase):
    def test_passes_sp_json_through_unchanged(self):
        with mock.patch.object(je, '_sp', return_value=SAMPLE) as sp:
            resp = je.journal_entries_balance_sheet_sp({"journalEntries": [{"companyId": 1, "asOfDate": "2026-09-30"}]})
        sp.assert_called_once_with("sp_journalEntries_balanceSheet",
                                   {"journalEntries": [{"companyId": 1, "asOfDate": "2026-09-30"}]})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(json.loads(resp.body), SAMPLE)

    def test_sp_error_is_400(self):
        with mock.patch.object(je, '_sp', return_value={"error": "companyId es requerido y debe existir."}):
            resp = je.journal_entries_balance_sheet_sp({"journalEntries": [{}]})
        self.assertEqual(resp.status_code, 400)

    def test_exception_is_500(self):
        with mock.patch.object(je, '_sp', side_effect=RuntimeError("db down")):
            resp = je.journal_entries_balance_sheet_sp({"journalEntries": [{"companyId": 1}]})
        self.assertEqual(resp.status_code, 500)


if __name__ == '__main__':
    unittest.main(verbosity=2)
