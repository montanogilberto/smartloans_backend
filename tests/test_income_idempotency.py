"""
A retried POST /income (same income[0].clientRequestId) creates no second
sale: modules/income.py returns the sale that key already made, in the shape
of an insert, and skips sp_income and every hook. A concurrent retry that
loses the race on UQ_income_company_clientRequestId has its copy deleted.

Run:  venv/bin/python -m unittest tests/test_income_idempotency.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import modules.income as income  # noqa: E402


class DuplicateKey(Exception):
    def __init__(self):
        super().__init__(2601, b"Cannot insert duplicate key row in object 'dbo.income'")


class FakeDb:
    """dbo.income keyed by (companyId, clientRequestId), shared by every
    connection, plus a log of every statement."""

    def __init__(self):
        self.log, self.keys, self.next_id = [], {}, 5000
        self.discounts_result = None
        self.sale_total = {"total": 90.0, "discountAmount": None, "promotionCode": None}
        self.on_insert = None  # runs after sp_income inserts, before the key is stored
        self.missing_column = False

    def connect(self):
        return FakeConn(self)


class FakeCursor:
    def __init__(self, db):
        self.db, self.rows = db, []

    def execute(self, sql, params=None):
        db = self.db
        db.log.append((sql, params))
        self.rows = []
        if db.missing_column and "clientRequestId" in sql:
            raise Exception("Invalid column name 'clientRequestId'.")
        if "sp_income_applyDiscounts" in sql:
            self.rows = [(json.dumps(db.discounts_result),)]
        elif "sp_income_one" in sql:
            income_id = json.loads(params[0])["income"][0]["incomeId"]
            self.rows = [(json.dumps({"income": [dict(db.sale_total, incomeId=income_id)]}),)]
        elif "sp_income " in sql:
            row = json.loads(params[0])["income"][0]
            if row["action"] == 1:
                db.next_id += 1
                self.rows = [(str(db.next_id), "Inserted Successfully", "0")]
                if db.on_insert:
                    db.on_insert()
            else:
                self.rows = [(str(row["incomeId"]), "Deleted Successfully", "0")]
        elif "sp_getapplock" in sql:
            self.rows = [(0,)]
        elif sql.startswith("SELECT incomeId FROM dbo.income"):
            found = db.keys.get(params)
            self.rows = [(found,)] if found else []
        elif sql.startswith("UPDATE dbo.income SET clientRequestId"):
            key, income_id = params
            if any(k[1] == key for k in db.keys):
                raise DuplicateKey()
            db.keys[(1, key)] = income_id

    def fetchall(self):
        return self.rows

    def fetchone(self):
        return self.rows[0] if self.rows else None


class FakeConn:
    def __init__(self, db):
        self.db = db

    def cursor(self):
        return FakeCursor(self.db)

    def commit(self):
        pass

    def close(self):
        pass


def sale(**extra):
    row = {"action": 1, "companyId": 1, "clientId": 2260, "userId": 7, "total": 90, "paymentMethod": "Efectivo",
           "paymentDate": "2026-10-18T19:00:00.000Z", "clientRequestId": "b1f0c3e2-6f1e-4d7a-9a51-0c2d9e4f7a11"}
    row.update(extra)
    return {"income": [row]}


class IncomeIdempotencyTest(unittest.TestCase):
    def setUp(self):
        self.db = FakeDb()
        patches = [
            mock.patch.object(income, "connection", side_effect=self.db.connect),
            mock.patch.object(income, "post_income_journal_entry"),
            mock.patch.object(income, "post_income_commission_journal_entry"),
            mock.patch.object(income, "earn_points_for_income"),
            mock.patch.object(income, "_get_client_phone", return_value=None),
        ]
        self.mocks = [p.start() for p in patches]
        self.post_income, self.earn = self.mocks[1], self.mocks[3]
        for p in patches:
            self.addCleanup(p.stop)

    def _post(self, payload):
        return json.loads(income.income_sp(payload).body)

    def _calls(self, proc):
        return [json.loads(p[0]) for (sql, p) in self.db.log if proc in sql and p]

    def _inserts(self):
        return [c for c in self._calls("sp_income @") if c["income"][0]["action"] == 1]

    def test_repeated_payload_inserts_once_and_returns_same_income(self):
        first = self._post(sale(promotionCode="2X1"))
        second = self._post(sale(promotionCode="2X1"))
        self.assertEqual(len(self._inserts()), 1)
        self.assertEqual(first["result"][0]["value"], "5001")
        self.assertEqual(second["result"][0], {"value": "5001", "msg": "Inserted Successfully", "error": "0"})
        self.assertNotIn("clientRequestId", self._inserts()[0]["income"][0])

    def test_retry_runs_no_hooks_again(self):
        self.db.discounts_result = {"result": [{"incomeId": 5001, "total": 90.0, "applied": [], "rejected": []}]}
        self._post(sale(promotionCode="2X1"))
        self._post(sale(promotionCode="2X1"))
        self.assertEqual(len(self._calls("sp_income_applyDiscounts")), 1)
        self.assertEqual(self.post_income.call_count, 1)
        self.assertEqual(self.earn.call_count, 1)

    def test_retry_reports_the_discount_the_sale_got(self):
        self._post(sale())
        self.db.sale_total = {"total": 90.0, "discountAmount": 90.0, "promotionCode": "2X1"}
        discounts = self._post(sale())["result"][0]["discounts"]
        self.assertEqual((discounts["total"], discounts["discountAmount"], discounts["rejected"]), (90.0, 90.0, []))

    def test_new_key_or_no_key_is_a_new_sale(self):
        self._post(sale())
        self._post(sale(clientRequestId="another-checkout"))
        no_key = sale()
        del no_key["income"][0]["clientRequestId"]
        self._post(no_key)
        self._post(json.loads(json.dumps(no_key)))
        self.assertEqual(len(self._inserts()), 4)

    def test_concurrent_retry_losing_the_race_deletes_its_copy(self):
        # Another request stores the same key between our insert and our UPDATE.
        self.db.on_insert = lambda: self.db.keys.setdefault((1, sale()["income"][0]["clientRequestId"]), 4999)
        body = self._post(sale())
        self.assertEqual(body["result"][0]["value"], "4999")
        deletes = [c["income"][0] for c in self._calls("sp_income @") if c["income"][0]["action"] == 2]
        self.assertEqual(deletes, [{"action": 2, "incomeId": 5001, "companyId": 1}])
        self.assertEqual(self.post_income.call_count, 0)

    def test_missing_column_still_sells(self):
        self.db.missing_column = True  # 2026-10-18c not run yet
        body = self._post(sale())
        self.assertEqual(body["result"][0]["value"], "5001")
        self.assertEqual(self.post_income.call_count, 1)

if __name__ == "__main__":
    unittest.main()
