"""
Company token ledger — module wrapper + route guards.

The SQL itself was exercised against the live schema inside a rolled-back
transaction (see sql/migrations/2026-10-02c_company_token_ledger.sql); these
tests cover the Python layer: JSON in/out, error mapping, and that usage can
only be recorded / topped up with the shared worker key.

Run:  venv/bin/python -m unittest tests/test_company_tokens.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.companyTokens as ct  # noqa: E402
import routes_.companyTokens as routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402


def _fake_connection(rows):
    cursor = mock.MagicMock()
    cursor.fetchall.return_value = rows
    conn = mock.MagicMock()
    conn.cursor.return_value = cursor
    return conn, cursor


class ModuleTest(unittest.TestCase):
    def test_balance_parses_the_sp_json(self):
        sp_json = {"ok": True, "companyId": 1, "balance": 995679, "usedToday": 4321}
        conn, cursor = _fake_connection([(json.dumps(sp_json),)])
        with mock.patch.object(ct, "connection", return_value=conn):
            resp = ct.company_tokens_balance_sp({"tokens": [{"companyId": 1}]})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(json.loads(resp.body), sp_json)
        sql, params = cursor.execute.call_args[0]
        self.assertIn("sp_companyTokens_balance", sql)
        self.assertEqual(json.loads(params[0]), {"tokens": [{"companyId": 1}]})
        conn.close.assert_called_once()

    def test_json_split_across_rows_is_joined(self):
        # SQL Server splits long FOR JSON output into several rows.
        conn, _ = _fake_connection([('{"ok":tr',), ('ue,"balance":5}',)])
        with mock.patch.object(ct, "connection", return_value=conn):
            resp = ct.company_tokens_balance_sp({"tokens": [{"companyId": 1}]})
        self.assertEqual(json.loads(resp.body), {"ok": True, "balance": 5})

    def test_no_rows_is_an_empty_object_not_a_crash(self):
        conn, _ = _fake_connection([])
        with mock.patch.object(ct, "connection", return_value=conn):
            resp = ct.company_tokens_record_sp({"tokens": [{"companyId": 1}]})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(json.loads(resp.body), {})

    def test_database_failure_is_500_and_connection_closed(self):
        conn, cursor = _fake_connection([])
        cursor.execute.side_effect = RuntimeError("db down")
        with mock.patch.object(ct, "connection", return_value=conn):
            resp = ct.company_tokens_topup_sp({"tokens": [{"companyId": 1, "tokens": 10}]})
        self.assertEqual(resp.status_code, 500)
        conn.close.assert_called_once()


class RouteGuardTest(unittest.TestCase):
    def setUp(self):
        self._key = mock.patch.object(worker_key, "WORKER_KEY", "secret123")
        self._key.start()
        self.addCleanup(self._key.stop)
        self._sp = mock.patch.object(ct, "_call_sp")
        self.call_sp = self._sp.start()
        self.addCleanup(self._sp.stop)
        from fastapi.responses import JSONResponse
        self.call_sp.side_effect = lambda sp, payload: JSONResponse({"sp": sp})
        app = FastAPI()
        app.include_router(routes.router)
        self.client = TestClient(app)
        self.body = {"tokens": [{"companyId": 1}]}

    def test_balance_is_open_like_other_read_endpoints(self):
        r = self.client.post("/company_tokens/balance", json=self.body)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json(), {"sp": "sp_companyTokens_balance"})

    def test_record_requires_the_worker_key(self):
        self.assertEqual(self.client.post("/company_tokens/record", json=self.body).status_code, 403)
        self.assertEqual(
            self.client.post("/company_tokens/record", json=self.body, headers={"x-worker-key": "nope"}).status_code, 403)
        ok = self.client.post("/company_tokens/record", json=self.body, headers={"x-worker-key": "secret123"})
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(ok.json(), {"sp": "sp_companyTokens_record"})

    def test_topup_requires_the_worker_key(self):
        self.assertEqual(self.client.post("/company_tokens/topup", json=self.body).status_code, 403)
        ok = self.client.post("/company_tokens/topup", json=self.body, headers={"x-worker-key": "secret123"})
        self.assertEqual(ok.status_code, 200)

    def test_without_a_configured_key_nothing_is_accepted(self):
        with mock.patch.object(worker_key, "WORKER_KEY", ""):
            r = self.client.post("/company_tokens/record", json=self.body, headers={"x-worker-key": ""})
        self.assertEqual(r.status_code, 403)


if __name__ == "__main__":
    unittest.main()
