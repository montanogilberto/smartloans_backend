"""
/addresses: who may read/write a client's addresses, and how the module talks
to sp_addresses. Nothing reaches the database: connection() is mocked.

Run:  venv/bin/python -m unittest tests/test_addresses.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.addresses as addresses  # noqa: E402
import routes_.address as address_routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402
from security import session_tokens  # noqa: E402

SECRET = "s" * 40

app = FastAPI()
app.include_router(address_routes.router)
client = TestClient(app)


def _cursor(fetchone=None, fetchall=None):
    cursor = mock.MagicMock()
    cursor.fetchone.return_value = fetchone
    cursor.fetchall.return_value = fetchall or []
    conn = mock.MagicMock()
    conn.cursor.return_value = cursor
    return conn, cursor


class GuardTest(unittest.TestCase):
    def setUp(self):
        for patcher in (mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": SECRET}),
                        mock.patch.object(worker_key, "WORKER_KEY", "right-key")):
            patcher.start()
            self.addCleanup(patcher.stop)
        conn, _ = _cursor(fetchall=[('{"addresses":[]}',)])
        patcher = mock.patch.object(addresses, "connection", return_value=conn)
        patcher.start()
        self.addCleanup(patcher.stop)

    def post(self, headers, company_id=1008, client_id=21):
        return client.post("/addresses/client",
                           json={"addresses": [{"companyId": company_id, "clientId": client_id}]},
                           headers=headers)

    @staticmethod
    def bearer(user_id, company_id, client_id, role):
        token = session_tokens.issue_session(user_id, company_id, client_id, role)["accessToken"]
        return {"Authorization": f"Bearer {token}"}

    def test_client_reads_own_addresses(self):
        self.assertEqual(self.post(self.bearer(7, 1008, 21, "borrower")).status_code, 200)

    def test_client_cannot_read_another_client(self):
        self.assertEqual(self.post(self.bearer(7, 1008, 22, "borrower")).status_code, 403)

    def test_client_cannot_read_in_another_company(self):
        self.assertEqual(self.post(self.bearer(7, 1, 21, "borrower"), company_id=1008).status_code, 403)

    def test_staff_of_the_company(self):
        self.assertEqual(self.post(self.bearer(9, 1008, 0, "manager")).status_code, 200)

    def test_staff_of_another_company(self):
        self.assertEqual(self.post(self.bearer(9, 1, 0, "manager")).status_code, 403)

    def test_worker_key(self):
        self.assertEqual(self.post({"X-Worker-Key": "right-key"}).status_code, 200)

    def test_no_credentials(self):
        self.assertEqual(self.post({}).status_code, 403)

    def test_expired_or_bad_token_asks_to_refresh(self):
        self.assertEqual(self.post({"Authorization": "Bearer nonsense"}).status_code, 401)

    def test_more_than_one_row_is_refused(self):
        headers = self.bearer(7, 1008, 21, "borrower")
        r = client.post("/addresses/client", headers=headers,
                        json={"addresses": [{"companyId": 1008, "clientId": 21},
                                            {"companyId": 1008, "clientId": 22}]})
        self.assertEqual(r.status_code, 403)


class ModuleTest(unittest.TestCase):
    def test_upsert_sends_one_row_and_returns_the_id(self):
        conn, cursor = _cursor(fetchone=("42", "Domicilio guardado", ""))
        row = {"action": 1, "companyId": 1008, "clientId": 21, "source": "gps", "fullAddress": "x"}
        with mock.patch.object(addresses, "connection", return_value=conn):
            r = addresses.addresses_sp({"addresses": [row]})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(json.loads(r.body)["value"], 42)
        sql, params = cursor.execute.call_args.args
        self.assertEqual(sql, "EXEC [dbo].[sp_addresses] @pjsonfile = %s")
        self.assertEqual(json.loads(params[0]), {"addresses": [row]})

    def test_sp_error_is_a_400_with_its_message(self):
        conn, _ = _cursor(fetchone=("", "El domicilio está vacío.", "1"))
        with mock.patch.object(addresses, "connection", return_value=conn):
            r = addresses.addresses_sp({"addresses": [{"action": 1}]})
        self.assertEqual(r.status_code, 400)
        self.assertEqual(json.loads(r.body)["message"], "El domicilio está vacío.")

    def test_database_failure_does_not_echo_the_address(self):
        with mock.patch.object(addresses, "connection", side_effect=RuntimeError("Calle Secreta 123")), \
                self.assertLogs("addresses", level="ERROR") as logs:
            r = addresses.addresses_sp({"addresses": [{"action": 1, "clientId": 21, "fullAddress": "Calle Secreta 123"}]})
        self.assertEqual(r.status_code, 500)
        self.assertNotIn("Secreta", r.body.decode())
        self.assertNotIn("Secreta", "".join(logs.output))

    def test_empty_read_is_an_empty_list(self):
        conn, _ = _cursor(fetchall=[])
        with mock.patch.object(addresses, "connection", return_value=conn):
            r = addresses.client_addresses_sp({"addresses": [{"companyId": 1008, "clientId": 21}]})
        self.assertEqual(json.loads(r.body), {"addresses": []})


if __name__ == "__main__":
    unittest.main()
