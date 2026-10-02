"""
Expense edit/delete -> ledger sync (modules/journalEntries.py + the hook in
modules/expenses.py). No database: the row lookup, the posted-entry lookup,
the account catalog and the SP call are stubbed, so this checks exactly which
entries get VOIDed / re-posted and in what order.

Run:  venv/bin/python -m unittest tests/test_expense_ledger_sync.py -v
Roadmap: POSVending/docs/accounting-module.md (posting map §7.3).
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.expenses as expenses  # noqa: E402
import modules.journalEntries as je  # noqa: E402

CATALOG = {
    1:    {'1101': 101, '1105': 105, '5105': 505, '5110': 510, '5115': 515},
    1008: {'1101': 9101, '1105': 9105, '5105': 9505, '5110': 9510, '5115': 9515},
}


def posted_entry(**over):
    base = {"entryId": 77, "companyId": 1, "entryDate": "2026-10-01", "amount": 100.0,
            "debitCode": "5105", "creditCode": "1101"}
    base.update(over)
    return base


def expense_row(**over):
    base = {"companyId": 1, "total": 100.0, "paymentMethod": "Efectivo", "expenseType": "inventory"}
    base.update(over)
    return base


class SyncBase(unittest.TestCase):
    def setUp(self):
        self.calls = []   # ordered ("void", entryId, companyId) / ("post", payload)
        self.catalog = CATALOG
        self.row, self.posted = expense_row(), [posted_entry()]
        self.void_error = None
        self.patches = [
            mock.patch.object(je, '_fetch_expense', side_effect=lambda _id: self.row),
            mock.patch.object(je, '_fetch_posted_expense_entries', side_effect=lambda _id: list(self.posted)),
            mock.patch.object(je, '_get_account_id', side_effect=lambda c, code: self.catalog.get(c, {}).get(code)),
            mock.patch.object(je, '_sp', side_effect=self._sp),
        ]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()

    def _sp(self, proc, payload):
        self.assertEqual(proc, 'sp_journalEntries')
        entry = payload['journalEntries'][0]
        if entry['action'] == 2:
            if self.void_error:
                return {"error": self.void_error}
            self.calls.append(("void", entry['entryId'], entry['companyId']))
            return {"entryId": entry['entryId']}
        self.calls.append(("post", entry))
        return {"entryId": 999}

    def posts(self):
        return [c[1] for c in self.calls if c[0] == "post"]

    def voids(self):
        return [c for c in self.calls if c[0] == "void"]


class ResyncTest(SyncBase):
    def test_unchanged_expense_touches_nothing(self):
        out = je.resync_expense_journal_entry(5)
        self.assertEqual(out["status"], "unchanged")
        self.assertEqual(self.calls, [])

    def test_changed_total_voids_then_reposts_with_same_date_and_accounts(self):
        self.row = expense_row(total=250.5)
        out = je.resync_expense_journal_entry(5)
        self.assertEqual(out, {"status": "reposted", "voided": [77]})
        self.assertEqual([c[0] for c in self.calls], ["void", "post"])   # void first: the duplicate guard
        entry = self.posts()[0]
        self.assertEqual((entry['referenceType'], entry['referenceId'], entry['entryDate']), ('expense', 5, '2026-10-01'))
        self.assertEqual([(l['accountId'], l['debit'], l['credit']) for l in entry['lines']],
                         [(505, 250.5, 0), (101, 0, 250.5)])

    def test_payment_method_change_moves_credit_caja_to_bancos(self):
        self.row = expense_row(paymentMethod="Tarjeta")
        je.resync_expense_journal_entry(5)
        self.assertEqual([l['accountId'] for l in self.posts()[0]['lines']], [505, 105])

    def test_expense_type_change_moves_debit_account(self):
        self.row = expense_row(expenseType="payroll")
        je.resync_expense_journal_entry(5)
        self.assertEqual([l['accountId'] for l in self.posts()[0]['lines']], [510, 101])

    def test_company_change_voids_in_old_company_and_posts_in_new(self):
        self.row = expense_row(companyId=1008)
        je.resync_expense_journal_entry(5)
        self.assertEqual(self.voids(), [("void", 77, 1)])
        entry = self.posts()[0]
        self.assertEqual(entry['companyId'], 1008)
        self.assertEqual([l['accountId'] for l in entry['lines']], [9505, 9101])

    def test_new_entry_date_reposts_but_same_date_does_not(self):
        je.resync_expense_journal_entry(5, new_entry_date="2026-10-01")
        self.assertEqual(self.calls, [])
        je.resync_expense_journal_entry(5, new_entry_date="2026-09-28")
        self.assertEqual(self.posts()[0]['entryDate'], "2026-09-28")

    def test_expense_with_no_entry_is_left_alone(self):
        # historic expenses are the backfill's business, never created by an edit
        self.posted = []
        self.row = expense_row(total=999)
        self.assertEqual(je.resync_expense_journal_entry(5)["status"], "no_entry")
        self.assertEqual(self.calls, [])

    def test_missing_accounts_keep_the_old_entry(self):
        self.catalog = {1: {'1101': 101}}   # no 5105
        self.row = expense_row(total=250)
        out = je.resync_expense_journal_entry(5)
        self.assertEqual(out["status"], "skipped_missing_accounts")
        self.assertEqual(self.calls, [])

    def test_void_failure_posts_nothing(self):
        self.row = expense_row(total=250)
        self.void_error = "boom"
        with self.assertRaises(RuntimeError):
            je.resync_expense_journal_entry(5)
        self.assertEqual(self.posts(), [])

    def test_repost_failure_is_reported_not_hidden(self):
        self.row = expense_row(total=250)
        with mock.patch.object(je, '_post_movement_journal_entry', return_value=False):
            out = je.resync_expense_journal_entry(5)
        self.assertEqual(out, {"status": "voided_repost_failed", "voided": [77]})

    def test_duplicate_posted_entries_are_all_voided_and_replaced_by_one(self):
        self.posted = [posted_entry(entryId=77), posted_entry(entryId=78)]
        out = je.resync_expense_journal_entry(5)
        self.assertEqual(out["voided"], [77, 78])
        self.assertEqual(len(self.posts()), 1)

    def test_zero_total_voids_without_reposting(self):
        self.row = expense_row(total=0)
        out = je.resync_expense_journal_entry(5)
        self.assertEqual((out["status"], len(self.posts())), ("voided", 0))

    def test_row_gone_is_treated_as_delete(self):
        self.row = None
        out = je.resync_expense_journal_entry(5)
        self.assertEqual((out["status"], out["voided"]), ("voided", [77]))


class VoidOnDeleteTest(SyncBase):
    def test_deleted_expense_voids_its_entry(self):
        out = je.void_expense_journal_entries(5)
        self.assertEqual(out, {"status": "voided", "voided": [77]})
        self.assertEqual(self.voids(), [("void", 77, 1)])
        self.assertEqual(self.posts(), [])

    def test_delete_with_no_entry_is_a_noop_and_idempotent(self):
        self.posted = []
        self.assertEqual(je.void_expense_journal_entries(5)["status"], "no_entry")
        self.assertEqual(self.calls, [])


# ── the hook in expense_sp ──────────────────────────────────────────────────
class FakeCursor:
    def __init__(self, rows):
        self.rows = rows

    def execute(self, sql, params=None):
        pass

    def fetchall(self):
        return self.rows


class FakeConn:
    def __init__(self, rows):
        self.rows = rows

    def cursor(self):
        return FakeCursor(self.rows)

    def close(self):
        pass


class HookTest(unittest.TestCase):
    def _run(self, payload, rows, **patches):
        defaults = {
            'post_expense_journal_entry': mock.DEFAULT, 'void_expense_journal_entries': mock.DEFAULT,
            'resync_expense_journal_entry': mock.DEFAULT, 'log_workflow_step': mock.DEFAULT, 'log_audit': mock.DEFAULT,
        }
        with mock.patch.object(expenses, 'connection', return_value=FakeConn(rows)):
            ctx = {name: mock.patch.object(expenses, name, **({'side_effect': patches[name]} if name in patches else {}))
                   for name in defaults}
            started = {name: p.start() for name, p in ctx.items()}
            try:
                expenses.expense_sp(payload)
            finally:
                for p in ctx.values():
                    p.stop()
        return started

    def test_successful_delete_voids_by_expense_id(self):
        m = self._run({"expenses": [{"action": 3, "expenseId": 1002}]}, [("", "Deleted Successfully", "")])
        m['void_expense_journal_entries'].assert_called_once_with(1002)
        m['resync_expense_journal_entry'].assert_not_called()
        m['post_expense_journal_entry'].assert_not_called()

    def test_successful_update_resyncs_with_normalized_payment_date(self):
        m = self._run({"expenses": [{"action": 2, "expenseId": 1002, "companyId": 1, "total": 50,
                                      "paymentDate": "2026-10-02T03:00:00.000Z"}]},
                      [("", "Updated Successfully", "")])
        # 03:00Z on the 2nd is still the 1st in Hermosillo (UTC-7)
        m['resync_expense_journal_entry'].assert_called_once_with(1002, new_entry_date="2026-10-01")
        m['void_expense_journal_entries'].assert_not_called()

    def test_update_without_payment_date_keeps_entry_date(self):
        m = self._run({"expenses": [{"action": 2, "expenseId": 1002, "receiptUrl": "https://x"}]},
                      [("", "Updated Successfully", "")])
        m['resync_expense_journal_entry'].assert_called_once_with(1002, new_entry_date=None)

    def test_failed_update_or_delete_never_touches_the_ledger(self):
        for action in (2, 3):
            m = self._run({"expenses": [{"action": action, "expenseId": 1002}]}, [("", "boom", "1")])
            m['resync_expense_journal_entry'].assert_not_called()
            m['void_expense_journal_entries'].assert_not_called()

    def test_insert_still_only_auto_posts(self):
        m = self._run({"expenses": [{"action": 1, "companyId": 1, "total": 10, "paymentMethod": "Efectivo",
                                      "paymentDate": "2026-10-01"}]}, [("1010", "Inserted Successfully", "")])
        m['post_expense_journal_entry'].assert_called_once()
        m['resync_expense_journal_entry'].assert_not_called()
        m['void_expense_journal_entries'].assert_not_called()

    def test_sync_error_never_breaks_the_expense_response(self):
        m = self._run({"expenses": [{"action": 3, "expenseId": 1002}]}, [("", "Deleted Successfully", "")],
                      void_expense_journal_entries=RuntimeError("ledger down"))
        m['void_expense_journal_entries'].assert_called_once_with(1002)   # raised inside, swallowed by the hook


if __name__ == "__main__":
    unittest.main()
