"""
Red GMO — host candidates (businesses offering space for a GMO locker).

Route guard (admin/manager of the company, no write route besides the staff
status change), the record_location_host() writer and the SQL value lists the
WhatsApp agent sends. No database: SPs are mocked; SQL files are only text-checked.

Run:  venv/bin/python -m unittest tests/test_location_hosts.py -v
"""
import os
import re
import sys
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)

os.environ.setdefault("SESSION_JWT_SECRET", "t" * 40)

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.locationHosts as lh  # noqa: E402
import routes_.locationHost as lh_routes  # noqa: E402
import security.rate_limit as rl  # noqa: E402
import security.session_tokens as st  # noqa: E402

LAUNDRY, GROCERY = 1, 2


class RouteGuardTest(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(lh_routes.router)
        self.client = TestClient(app)
        rl.reset()
        ok = JSONResponse({"result": [{"locationHosts": []}]})
        for p in (mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": "t" * 40}),
                  mock.patch("security.worker_key.WORKER_KEY", "wk"),
                  mock.patch.object(lh_routes, "all_locationHosts_sp", return_value=ok),
                  mock.patch.object(lh_routes, "status_locationHosts_sp", return_value=ok)):
            p.start()
        self.addCleanup(mock.patch.stopall)

    def _post(self, path="/all_locationHosts", token=None, company=LAUNDRY, user=9):
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        return self.client.post(path, headers=headers, json={"locationHosts": [
            {"companyId": company, "userId": user, "locationHostId": 4, "status": "contactado"}]})

    def test_anonymous_is_refused(self):
        self.assertEqual(self._post().status_code, 403)
        self.assertEqual(self._post("/locationHosts/status").status_code, 403)

    def test_admin_and_manager_pass(self):
        for role in ("admin", "manager"):
            token = st.issue_session(9, LAUNDRY, 0, role)["accessToken"]
            self.assertEqual(self._post(token=token).status_code, 200, role)
            self.assertEqual(self._post("/locationHosts/status", token=token).status_code, 200, role)

    def test_employee_and_other_company_are_refused(self):
        token = st.issue_session(9, LAUNDRY, 0, "employee")["accessToken"]
        self.assertEqual(self._post(token=token).status_code, 403)
        token = st.issue_session(9, GROCERY, 0, "admin")["accessToken"]
        self.assertEqual(self._post("/locationHosts/status", token=token).status_code, 403)

    def test_only_list_and_status_routes(self):
        self.assertEqual({r.path for r in lh_routes.router.routes},
                         {"/all_locationHosts", "/locationHosts/status"})


class RecordLocationHostTest(unittest.TestCase):
    def test_returns_id_and_status(self):
        with mock.patch.object(lh, "_exec", return_value={"result": [{"locationHostId": 4, "status": "nuevo"}]}) as ex:
            out = lh.record_location_host({"locationHosts": [{"companyId": 1}]})
        self.assertEqual(out, {"locationHostId": 4, "status": "nuevo"})
        self.assertEqual(ex.call_args.args[0], "sp_locationHosts")

    def test_sp_error_raises(self):
        with mock.patch.object(lh, "_exec", return_value={"error": "channel does not belong to company"}):
            with self.assertRaises(RuntimeError):
                lh.record_location_host({"locationHosts": [{"companyId": 1}]})


def _check_list(sql: str, column: str) -> set[str]:
    m = re.search(rf"CHECK \({column} IN\s*\(([^)]*)\)\)", sql)
    return set(re.findall(r"'([^']+)'", m.group(1))) if m else set()


class SqlContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open("sql/migrations/2026-11-10_locationHosts.sql", encoding="utf-8") as f:
            cls.table = f.read()
        with open("sql/sp_locationHosts.sql", encoding="utf-8") as f:
            cls.upsert = re.sub(r"--.*", "", f.read())
        with open("sql/sp_locationHosts_status.sql", encoding="utf-8") as f:
            cls.status = re.sub(r"--.*", "", f.read())

    def test_value_lists_match_the_agent_contract(self):
        expected = {
            "origin": {"anuncio", "organico", "personal"},
            "businessType": {"tienda", "gimnasio", "farmacia", "oficina", "escuela", "gasolinera",
                             "restaurante", "otro"},
            "contactRole": {"dueno", "encargado", "otro"},
            "spaceType": {"interior", "exterior", "estacionamiento", "no_seguro"},
            "dailyVisitors": {"menos_50", "50_200", "mas_200", "no_seguro"},
            "status": {"nuevo", "contactado", "visitado", "aprobado", "instalado", "descartado"},
        }
        for column, values in expected.items():
            self.assertEqual(_check_list(self.table, column), values, column)

    def test_timestamps_are_datetime2(self):
        self.assertNotRegex(self.table, r"\bDATETIME\b(?!2)")

    def test_upsert_never_touches_status_or_notes_and_checks_tenant(self):
        update = re.split(r"UPDATE\s+dbo\.locationHosts\s+SET", self.upsert, maxsplit=1)[1]  # a regex: a plain SQL string trips check_raw_sql
        self.assertNotRegex(update, r"\bstatus\s*=|staffNotes\s*=")
        self.assertNotIn("DELETE", self.upsert.upper())
        self.assertIn("channel does not belong to company", self.upsert)

    def test_status_update_is_scoped_to_company(self):
        self.assertIn("WHERE locationHostId = @id AND companyId = @companyId", self.status)


if __name__ == "__main__":
    unittest.main()
