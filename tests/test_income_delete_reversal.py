"""
Step 5 gate (Python side) — deleting a sale triggers sp_income_reverseOnDelete,
and nothing else creates journal entries for points.

Run:  venv/bin/python -m unittest tests/test_income_delete_reversal.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.income as income  # noqa: E402


class FakeCursor:
    def __init__(self, log, sp_income_rows, reverse_row):
        self.log, self.sp_income_rows, self.reverse_row = log, sp_income_rows, reverse_row

    def execute(self, sql, params=None):
        self.log.append((sql, params))

    def fetchall(self):
        return self.sp_income_rows

    def fetchone(self):
        return self.reverse_row


class FakeConn:
    def __init__(self, sp_income_rows, reverse_row=(2, 15.0, 0.0, 0, 0, False)):
        self.log = []
        self.sp_income_rows, self.reverse_row = sp_income_rows, reverse_row

    def cursor(self):
        return FakeCursor(self.log, self.sp_income_rows, self.reverse_row)

    def commit(self):
        pass

    def close(self):
        pass


class DeleteReversalTest(unittest.TestCase):
    def _run(self, payload, sp_rows):
        conn = FakeConn(sp_rows)
        with mock.patch.object(income, 'connection', return_value=conn), \
             mock.patch.object(income, 'post_income_journal_entry') as post_income, \
             mock.patch.object(income, 'post_income_commission_journal_entry') as post_commission, \
             mock.patch.object(income, 'earn_points_for_income') as earn:
            income.income_sp(payload)
        return conn, post_income, post_commission, earn

    def _reverse_calls(self, conn):
        return [p for (sql, p) in conn.log if 'sp_income_reverseOnDelete' in sql]

    def test_successful_delete_calls_reversal_once(self):
        conn, post_income, post_commission, earn = self._run(
            {"income": [{"action": 2, "incomeId": 4320}]}, [("4320", "Deleted Successfully", "0")])
        self.assertEqual(self._reverse_calls(conn), [(4320,)])
        # a delete never posts a sale, a commission or earns points
        post_income.assert_not_called(); post_commission.assert_not_called(); earn.assert_not_called()

    def test_failed_delete_does_not_reverse(self):
        conn, *_ = self._run({"income": [{"action": 2, "incomeId": 4320}]}, [("", "incomeId required", "1")])
        self.assertEqual(self._reverse_calls(conn), [])

    def test_delete_without_income_id_does_not_reverse(self):
        conn, *_ = self._run({"income": [{"action": 2}]}, [("", "incomeId required", "1")])
        self.assertEqual(self._reverse_calls(conn), [])

    def test_new_sale_never_reverses(self):
        conn, *_ = self._run(
            {"income": [{"action": 1, "companyId": 1, "clientId": 1, "total": 100, "paymentMethod": "Efectivo",
                         "paymentDate": "2026-09-30T19:00:00.000Z"}]},
            [("5000", "Inserted Successfully", "0")])
        self.assertEqual(self._reverse_calls(conn), [])

    def test_reversal_failure_never_breaks_the_delete_response(self):
        conn = FakeConn([("4320", "Deleted Successfully", "0")])

        def boom(*_a, **_k):
            raise RuntimeError("db down")
        with mock.patch.object(income, 'connection', return_value=conn), \
             mock.patch.object(income, '_reverse_on_delete', side_effect=boom):
            response = income.income_sp({"income": [{"action": 2, "incomeId": 4320}]})
        self.assertEqual(response.status_code, 200)


class PointsNeverJournaledTest(unittest.TestCase):
    """Q6 = purely promotional: no rewards module may post to the journal."""

    def test_rewards_modules_do_not_import_journal_posting(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        for name in ('rewards.py', 'posRewards.py', 'rewardBenefits.py'):
            with open(os.path.join(root, 'modules', name), encoding='utf-8') as fh:
                src = fh.read()
            # an import of the posting module or an EXEC of the journal SP
            # (docstrings may mention the journal; they don't post to it)
            self.assertNotIn('from modules.journalEntries', src, name)
            self.assertNotIn('import modules.journalEntries', src, name)
            self.assertNotIn('[sp_journalEntries]', src, name)
            self.assertNotIn('EXEC sp_journalEntries', src, name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
