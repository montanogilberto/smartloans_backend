"""
A new sale's coupon and loyalty reward come from dbo.posRewardCatalogItems:
modules/income.py strips them from the sp_income payload (whose own B2G1 block
reads the retired dbo.promotions) and applies them with
sp_income_applyDiscounts, before the accounting hooks price the sale.

Run:  venv/bin/python -m unittest tests/test_income_discounts.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.income as income  # noqa: E402


class FakeCursor:
    def __init__(self, conn):
        self.conn, self.rows = conn, []

    def execute(self, sql, params=None):
        self.conn.log.append((sql, params))
        if "sp_income_applyDiscounts" in sql:
            self.rows = [(json.dumps(self.conn.discounts_result),)]
        elif "sp_income " in sql:
            self.rows = [("5000", "Inserted Successfully", "0")]
        else:
            self.rows = []

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return None


class FakeConn:
    def __init__(self, discounts_result):
        self.log, self.discounts_result = [], discounts_result

    def cursor(self):
        return FakeCursor(self)

    def commit(self):
        pass

    def close(self):
        pass


APPLIED = {"result": [{"incomeId": 5000, "subtotal": 180.0, "total": 90.0, "discountAmount": 90.0,
                       "promotionCode": "2X1", "applied": [{"catalogItemId": 12, "rewardType": "coupon_b2g1", "discount": 90.0}],
                       "rejected": []}]}


def sale(**extra):
    row = {"action": 1, "companyId": 1, "clientId": 2260, "userId": 7, "total": 90, "paymentMethod": "Efectivo",
           "paymentDate": "2026-10-16T19:00:00.000Z"}
    row.update(extra)
    return {"income": [row]}


class IncomeDiscountsTest(unittest.TestCase):
    def _run(self, payload, discounts_result=APPLIED):
        conn = FakeConn(discounts_result)
        with mock.patch.object(income, "connection", return_value=conn), \
             mock.patch.object(income, "post_income_journal_entry") as post_income, \
             mock.patch.object(income, "post_income_commission_journal_entry"), \
             mock.patch.object(income, "earn_points_for_income"), \
             mock.patch.object(income, "_get_client_phone", return_value=None):
            resp = income.income_sp(payload)
        return conn, post_income, json.loads(resp.body)

    def _calls(self, conn, proc):
        return [json.loads(p[0]) for (sql, p) in conn.log if proc in sql and p]

    def test_coupon_is_stripped_from_sp_income_and_applied_after(self):
        conn, post_income, body = self._run(sale(promotionCode="2x1", rewardCatalogItemIds=[5]))
        sp_income_row = self._calls(conn, "sp_income @")[0]["income"][0]
        self.assertNotIn("promotionCode", sp_income_row)
        self.assertNotIn("rewardCatalogItemIds", sp_income_row)
        self.assertEqual(self._calls(conn, "sp_income_applyDiscounts")[0], {"incomeDiscounts": [{
            "companyId": 1, "incomeId": 5000, "userId": 7, "couponCode": "2X1", "rewardCatalogItemIds": [5]}]})
        self.assertEqual(body["result"][0]["discounts"]["promotionCode"], "2X1")

    def test_accounting_uses_the_discounted_total(self):
        _, post_income, _ = self._run(sale(total=180, promotionCode="2X1"))
        self.assertEqual(post_income.call_args.args[2], 90.0)

    def test_no_coupon_no_reward_skips_apply(self):
        conn, post_income, body = self._run(sale())
        self.assertEqual(self._calls(conn, "sp_income_applyDiscounts"), [])
        self.assertNotIn("discounts", body["result"][0])
        self.assertEqual(post_income.call_args.args[2], 90.0)

    def test_apply_error_keeps_the_sale_and_the_pos_total(self):
        _, post_income, body = self._run(sale(total=180, promotionCode="2X1"), {"error": "boom"})
        self.assertEqual(body["result"][0]["error"], "0")
        self.assertNotIn("discounts", body["result"][0])
        self.assertEqual(post_income.call_args.args[2], 180.0)

    def test_updates_pass_promotion_code_through(self):
        payload = {"income": [{"action": 3, "incomeId": 5000, "promotionCode": "2X1"}]}
        self.assertEqual(income._take_discounts(payload), (None, []))
        self.assertEqual(payload["income"][0]["promotionCode"], "2X1")


if __name__ == "__main__":
    unittest.main()
