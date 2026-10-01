"""
Step 3 gate — auto-posting map (modules/journalEntries.py).
No database: account lookup and the SP call are stubbed, so this checks exactly
which accounts each movement debits/credits and that every entry balances.

Run:  venv/bin/python -m unittest tests/test_journal_posting_map.py -v
Roadmap: POSVending/docs/accounting-module.md §7.3.
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.journalEntries as je  # noqa: E402

# Fake catalog: one accountId per code, per company (isolation is checked by
# giving each company different ids).
CATALOG = {
    1:    {'1101': 101, '1105': 105, '4105': 405, '5105': 505, '5110': 510, '5115': 515, '5120': 520},
    1008: {'1101': 9101, '1105': 9105, '4105': 9405, '5105': 9505, '5110': 9510, '5115': 9515, '5120': 9520},
}


def fake_get_account_id(company_id, code):
    return CATALOG.get(company_id, {}).get(code)


class PostingMapTest(unittest.TestCase):
    def setUp(self):
        self.posted = []
        self.p1 = mock.patch.object(je, '_get_account_id', side_effect=fake_get_account_id)
        self.p2 = mock.patch.object(je, '_sp', side_effect=self._capture)
        self.p1.start(); self.p2.start()

    def tearDown(self):
        self.p1.stop(); self.p2.stop()

    def _capture(self, proc, payload):
        self.assertEqual(proc, 'sp_journalEntries')
        self.posted.append(payload['journalEntries'][0])
        return {'entryId': len(self.posted)}

    def _only_entry(self):
        self.assertEqual(len(self.posted), 1, 'expected exactly one journal entry')
        e = self.posted[0]
        debit = [l for l in e['lines'] if l['debit'] > 0]
        credit = [l for l in e['lines'] if l['credit'] > 0]
        self.assertEqual(len(debit), 1)
        self.assertEqual(len(credit), 1)
        self.assertEqual(debit[0]['debit'], credit[0]['credit'], 'entry must balance')
        return e, debit[0]['accountId'], credit[0]['accountId'], debit[0]['debit']

    # ── income ──────────────────────────────────────────────────────────────
    def test_cash_income_goes_to_caja(self):
        je.post_income_journal_entry(1, 501, 100.0, '2026-09-30T19:00:00.000Z', payment_method='Efectivo')
        e, dr, cr, amt = self._only_entry()
        self.assertEqual((dr, cr, amt), (101, 405, 100.0))           # Dr 1101 Caja / Cr 4105
        self.assertEqual((e['referenceType'], e['referenceId'], e['entryDate']), ('income', 501, '2026-09-30'))

    def test_card_income_goes_to_bancos(self):
        je.post_income_journal_entry(1, 502, 100.0, '2026-09-30', payment_method='Tarjeta')
        _, dr, cr, _ = self._only_entry()
        self.assertEqual((dr, cr), (105, 405))                        # Dr 1105 Bancos / Cr 4105

    def test_transfer_income_goes_to_bancos(self):
        je.post_income_journal_entry(1, 503, 80.0, '2026-09-30', payment_method='Transferencia')
        _, dr, cr, _ = self._only_entry()
        self.assertEqual((dr, cr), (105, 405))

    def test_payment_method_is_case_and_space_insensitive(self):
        je.post_income_journal_entry(1, 504, 10.0, '2026-09-30', payment_method='  EFECTIVO ')
        _, dr, _, _ = self._only_entry()
        self.assertEqual(dr, 101)

    def test_unknown_method_keeps_bancos(self):
        je.post_income_journal_entry(1, 505, 10.0, '2026-09-30', payment_method='vale')
        _, dr, _, _ = self._only_entry()
        self.assertEqual(dr, 105)

    # ── expenses ────────────────────────────────────────────────────────────
    def test_cash_payroll(self):
        je.post_expense_journal_entry(1, 601, 2300.0, '2026-09-29', payment_method='Efectivo', expense_type='payroll')
        e, dr, cr, amt = self._only_entry()
        self.assertEqual((dr, cr, amt), (510, 101, 2300.0))          # Dr 5110 Nómina / Cr 1101 Caja
        self.assertEqual((e['referenceType'], e['referenceId']), ('expense', 601))

    def test_bank_payroll(self):
        je.post_expense_journal_entry(1, 602, 2300.0, '2026-09-29', payment_method='Transferencia', expense_type='payroll')
        _, dr, cr, _ = self._only_entry()
        self.assertEqual((dr, cr), (510, 105))                        # Dr 5110 / Cr 1105 Bancos

    def test_general_expense_is_servicios(self):
        je.post_expense_journal_entry(1, 603, 50.0, '2026-09-29', payment_method='Efectivo', expense_type='general')
        _, dr, cr, _ = self._only_entry()
        self.assertEqual((dr, cr), (515, 101))                        # Dr 5115 Servicios / Cr 1101

    def test_inventory_expense_is_operacion_from_bank(self):
        je.post_expense_journal_entry(1, 604, 50.0, '2026-09-29', payment_method='Tarjeta', expense_type='inventory')
        _, dr, cr, _ = self._only_entry()
        self.assertEqual((dr, cr), (505, 105))                        # Dr 5105 / Cr 1105

    def test_missing_type_defaults_like_sp_expense(self):
        je.post_expense_journal_entry(1, 605, 50.0, '2026-09-29', payment_method='Tarjeta', expense_type=None)
        _, dr, _, _ = self._only_entry()
        self.assertEqual(dr, 505)

    # ── isolation & guards ──────────────────────────────────────────────────
    def test_company_isolation_uses_that_companys_accounts(self):
        je.post_income_journal_entry(1008, 701, 100.0, '2026-09-30', payment_method='Efectivo')
        e, dr, cr, _ = self._only_entry()
        self.assertEqual((e['companyId'], dr, cr), (1008, 9101, 9405))

    def test_missing_account_skips_instead_of_misposting(self):
        je.post_income_journal_entry(4242, 801, 100.0, '2026-09-30', payment_method='Efectivo')
        self.assertEqual(self.posted, [])

    def test_zero_or_negative_amount_is_not_posted(self):
        je.post_income_journal_entry(1, 802, 0, '2026-09-30', payment_method='Efectivo')
        je.post_expense_journal_entry(1, 803, -5, '2026-09-30', payment_method='Efectivo', expense_type='general')
        self.assertEqual(self.posted, [])

    def test_hermosillo_noon_timestamp_keeps_the_picked_day(self):
        # ExpenseForm sends noon Hermosillo (19:00Z) — the entry date must stay that day.
        je.post_expense_journal_entry(1, 804, 10.0, '2026-09-01T19:00:00.000Z', payment_method='Efectivo', expense_type='general')
        e, _, _, _ = self._only_entry()
        self.assertEqual(e['entryDate'], '2026-09-01')


    # ── Step 4: card commission ─────────────────────────────────────────────
    def test_commission_entry_dr_5120_cr_bancos(self):
        je.post_income_commission_journal_entry(1, 900, 4.2, '2026-09-30T19:00:00.000Z')
        e, dr, cr, amt = self._only_entry()
        self.assertEqual((dr, cr, amt), (520, 105, 4.2))              # Dr 5120 / Cr 1105
        self.assertEqual((e['referenceType'], e['referenceId'], e['entryDate']),
                         ('income_commission', 900, '2026-09-30'))

    def test_commission_amount_is_rounded_to_cents(self):
        je.post_income_commission_journal_entry(1, 901, '4.2049', '2026-09-30')
        _, _, _, amt = self._only_entry()
        self.assertEqual(amt, 4.2)

    def test_zero_or_missing_commission_is_not_posted(self):
        je.post_income_commission_journal_entry(1, 902, 0, '2026-09-30')
        je.post_income_commission_journal_entry(1, 903, None, '2026-09-30')
        self.assertEqual(self.posted, [])

    def test_card_sale_plus_commission_nets_95_80_in_bancos(self):
        # Acceptance test 3 / Rewards test B: $100 card sale, 4.2% commission.
        je.post_income_journal_entry(1, 904, 100.0, '2026-09-30T20:00:00.000Z', payment_method='Tarjeta')
        je.post_income_commission_journal_entry(1, 904, 4.2, '2026-09-30T20:00:00.000Z')
        self.assertEqual(len(self.posted), 2)
        bancos = sum(l['debit'] - l['credit'] for e in self.posted for l in e['lines'] if l['accountId'] == 105)
        ventas = sum(l['credit'] - l['debit'] for e in self.posted for l in e['lines'] if l['accountId'] == 405)
        comision = sum(l['debit'] - l['credit'] for e in self.posted for l in e['lines'] if l['accountId'] == 520)
        self.assertEqual((round(bancos, 2), ventas, comision), (95.8, 100.0, 4.2))
        self.assertEqual({e['entryDate'] for e in self.posted}, {'2026-09-30'})


class EntryDateTest(unittest.TestCase):
    """Hermosillo business date (UTC-7) — rule 22: no UTC-midnight regressions."""

    def test_date_only_is_kept(self):
        self.assertEqual(je._normalize_entry_date('2026-09-29'), '2026-09-29')

    def test_utc_evening_sale_stays_on_the_local_day(self):
        # 2026-10-01T02:30Z = 2026-09-30 19:30 in Hermosillo (the cart sends UTC ISO).
        self.assertEqual(je._normalize_entry_date('2026-10-01T02:30:00.000Z'), '2026-09-30')

    def test_utc_morning_sale(self):
        self.assertEqual(je._normalize_entry_date('2026-09-30T15:00:00Z'), '2026-09-30')

    def test_explicit_offset(self):
        self.assertEqual(je._normalize_entry_date('2026-09-30T23:59:00-07:00'), '2026-09-30')
        self.assertEqual(je._normalize_entry_date('2026-10-01T05:00:00+00:00'), '2026-09-30')

    def test_expense_form_noon(self):
        self.assertEqual(je._normalize_entry_date('2026-09-01T19:00:00.000Z'), '2026-09-01')

    def test_month_end_evening_does_not_jump_month(self):
        self.assertEqual(je._normalize_entry_date('2026-09-01T03:00:00.000Z'), '2026-08-31')

    def test_naive_timestamp_keeps_legacy_behavior(self):
        self.assertEqual(je._normalize_entry_date('2026-09-29T00:00:00'), '2026-09-29')


if __name__ == '__main__':
    unittest.main(verbosity=2)
