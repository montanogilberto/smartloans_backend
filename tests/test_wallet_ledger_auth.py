"""
RFC-011 P1.1 — POST /walletTransactions and /all_walletTransactions need the
worker key or a session allowed for that company/client.

Real signed tokens through the real routes; the SPs are mocked (no database).

Run:  venv/bin/python -m unittest tests/test_wallet_ledger_auth.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("SESSION_JWT_SECRET", "t" * 40)

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import app_env  # noqa: E402
import routes_.walletTransactions as wallet_tx_routes  # noqa: E402
import security.session_tokens as st  # noqa: E402

app = FastAPI()
app.include_router(wallet_tx_routes.router)
client = TestClient(app)

WRITE, READ = "/walletTransactions", "/all_walletTransactions"


def _token(role: str, company: int = 1, client_id: int = 0, user: int = 9) -> str:
    return st.issue_session(user, company, client_id, role)["accessToken"]


def _row(**over) -> dict:
    row = {"action": 1, "companyId": 1, "clientId": 2049, "entryType": "DEPOSIT", "direction": "C",
           "amountMXN": 100.0, "idempotencyKey": "k1"}
    row.update(over)
    return {"walletTransactions": [row]}


class WalletLedgerAuthTest(unittest.TestCase):
    def setUp(self):
        ok = JSONResponse({"entryId": 1, "balanceAfter": 100.0})
        patches = [
            mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": "t" * 40}),
            mock.patch("security.worker_key.WORKER_KEY", "wk"),
            mock.patch.object(app_env, "IS_PROD", True),
            mock.patch.object(wallet_tx_routes, "wallet_transactions_sp", return_value=ok),
            mock.patch.object(wallet_tx_routes, "all_wallet_transactions_sp",
                              return_value=JSONResponse({"walletTransactions": []})),
        ]
        for p in patches:
            p.start()
        self.addCleanup(mock.patch.stopall)

    def _post(self, path, body, token=None, worker_key=None):
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if worker_key:
            headers["X-Worker-Key"] = worker_key
        return client.post(path, json=body, headers=headers)

    # ── anonymous / worker ──────────────────────────────────────────────
    def test_anonymous_credit_is_refused(self):
        self.assertEqual(self._post(WRITE, _row()).status_code, 403)
        self.assertEqual(self._post(READ, _row()).status_code, 403)
        wallet_tx_routes.wallet_transactions_sp.assert_not_called()

    def test_worker_key_passes(self):
        self.assertEqual(self._post(WRITE, _row(), worker_key="wk").status_code, 200)
        self.assertEqual(self._post(READ, _row(), worker_key="wk").status_code, 200)

    def test_bad_or_expired_token_is_401(self):
        self.assertEqual(self._post(WRITE, _row(), token="nope").status_code, 401)

    # ── staff ───────────────────────────────────────────────────────────
    def test_admin_and_manager_write_their_company(self):
        for role in ("admin", "manager"):
            self.assertEqual(self._post(WRITE, _row(), token=_token(role)).status_code, 200, role)

    def test_cashier_reads_but_cannot_credit(self):
        token = _token("employee")
        self.assertEqual(self._post(READ, _row(), token=token).status_code, 200)
        self.assertEqual(self._post(WRITE, _row(), token=token).status_code, 403)

    def test_admin_of_another_company_is_refused(self):
        token = _token("admin", company=1008)
        self.assertEqual(self._post(WRITE, _row(), token=token).status_code, 403)
        self.assertEqual(self._post(READ, _row(), token=token).status_code, 403)

    def test_every_row_is_checked(self):
        body = _row()
        body["walletTransactions"].append(dict(body["walletTransactions"][0], companyId=1008))
        self.assertEqual(self._post(WRITE, body, token=_token("admin")).status_code, 403)

    # ── a client on their own ledger (the lender screen) ────────────────
    def test_lender_writes_capital_history_on_own_ledger(self):
        token = _token("lender", company=1008, client_id=3372)
        for entry in ("CAPITAL_DECLARED", "CAPITAL_UNDECLARED"):
            res = self._post(WRITE, _row(companyId=1008, clientId=3372, entryType=entry), token=token)
            self.assertEqual(res.status_code, 200, entry)
        self.assertEqual(self._post(READ, _row(companyId=1008, clientId=3372), token=token).status_code, 200)

    def test_client_cannot_credit_themselves_in_production(self):
        token = _token("pos", company=1, client_id=2049)
        for entry in ("DEPOSIT", "ADJUSTMENT", "REFUND", "REVERSAL"):
            self.assertEqual(self._post(WRITE, _row(entryType=entry), token=token).status_code, 403, entry)

    def test_simulated_deposit_only_outside_production(self):
        token = _token("lender", company=1008, client_id=3372)
        body = _row(companyId=1008, clientId=3372, entryType="DEPOSIT")
        with mock.patch.object(app_env, "IS_PROD", False):
            self.assertEqual(self._post(WRITE, body, token=token).status_code, 200)

    def test_client_cannot_touch_another_clients_ledger(self):
        token = _token("lender", company=1008, client_id=3372)
        other = _row(companyId=1008, clientId=3373, entryType="CAPITAL_DECLARED")
        self.assertEqual(self._post(WRITE, other, token=token).status_code, 403)
        self.assertEqual(self._post(READ, other, token=token).status_code, 403)

    def test_client_cannot_read_the_platform_ledger(self):
        token = _token("lender", company=1008, client_id=3372)
        self.assertEqual(self._post(READ, _row(companyId=1008, clientId=None), token=token).status_code, 403)

    def test_malformed_body_is_refused(self):
        for body in ({}, {"walletTransactions": []}, {"walletTransactions": ["x"]}):
            self.assertEqual(self._post(WRITE, body, token=_token("admin")).status_code, 403)


if __name__ == "__main__":
    unittest.main()
