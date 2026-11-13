"""
Client Acquisition — demand signals (location validation).

Route guard (admin/manager of the company only, read-only routes), the
record_demand_signal() writer and the SQL value lists the WhatsApp agent sends.
No database: SPs are mocked; SQL files are only text-checked.

Run:  venv/bin/python -m unittest tests/test_demand_signals.py -v
"""
import json
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

import modules.demandSignals as ds  # noqa: E402
import routes_.demandSignal as ds_routes  # noqa: E402
import security.session_tokens as st  # noqa: E402

LAUNDRY, GROCERY = 1, 2


class RouteGuardTest(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(ds_routes.router)
        self.client = TestClient(app)
        ok = JSONResponse({"result": [{"demandSignals": []}]})
        for p in (mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": "t" * 40}),
                  mock.patch("security.worker_key.WORKER_KEY", "wk"),
                  mock.patch.object(ds_routes, "all_demandSignals_sp", return_value=ok),
                  mock.patch.object(ds_routes, "zone_summary_demandSignals_sp", return_value=ok)):
            p.start()
        self.addCleanup(mock.patch.stopall)

    def _post(self, path="/all_demandSignals", token=None, company=LAUNDRY, user=9, worker=None):
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        if worker:
            headers["X-Worker-Key"] = worker
        return self.client.post(path, headers=headers,
                                json={"demandSignals": [{"companyId": company, "userId": user}]})

    def test_anonymous_is_refused(self):
        self.assertEqual(self._post().status_code, 403)

    def test_worker_key_passes(self):
        self.assertEqual(self._post(worker="wk").status_code, 200)

    def test_admin_and_manager_of_the_company_pass(self):
        for role in ("admin", "manager"):
            token = st.issue_session(9, LAUNDRY, 0, role)["accessToken"]
            self.assertEqual(self._post(token=token).status_code, 200, role)
            self.assertEqual(self._post("/demandSignals/zoneSummary", token=token).status_code, 200, role)

    def test_employee_is_refused(self):
        token = st.issue_session(9, LAUNDRY, 0, "employee")["accessToken"]
        self.assertEqual(self._post(token=token).status_code, 403)

    def test_other_company_or_other_user_is_refused(self):
        token = st.issue_session(9, GROCERY, 0, "admin")["accessToken"]
        self.assertEqual(self._post(token=token).status_code, 403)
        token = st.issue_session(10, LAUNDRY, 0, "admin")["accessToken"]
        self.assertEqual(self._post(token=token).status_code, 403)

    def test_there_is_no_write_route(self):
        paths = {r.path for r in ds_routes.router.routes}
        self.assertEqual(paths, {"/all_demandSignals", "/one_demandSignals", "/demandSignals/zoneSummary"})

    def test_default_staff_guard_unchanged(self):
        # roles=None keeps the old behaviour (employees allowed) for existing callers.
        app = FastAPI()

        @app.post("/x", dependencies=[mock.sentinel and __import__("fastapi").Depends(
            st.require_company_staff_session("rows"))])
        def x():
            return {"ok": True}
        token = st.issue_session(9, LAUNDRY, 0, "employee")["accessToken"]
        r = TestClient(app).post("/x", headers={"Authorization": f"Bearer {token}"},
                                 json={"rows": [{"companyId": LAUNDRY, "userId": 9}]})
        self.assertEqual(r.status_code, 200)


class _Cursor:
    def __init__(self, payload):
        self.payload, self.sql = payload, None

    def execute(self, sql, args=None):
        self.sql, self.args = sql, args

    def fetchall(self):
        return [(self.payload,)]


class _Conn:
    def __init__(self, payload):
        self.cur = _Cursor(payload)

    def cursor(self):
        return self.cur

    def close(self):
        pass


class RecordDemandSignalTest(unittest.TestCase):
    def test_returns_id_and_intent(self):
        conn = _Conn('{"result":[{"demandSignalId":7,"intentLevel":"alta"}]}')
        with mock.patch.object(ds, "connection", return_value=conn):
            out = ds.record_demand_signal({"demandSignals": [{"companyId": 1}]})
        self.assertEqual(out, {"demandSignalId": 7, "intentLevel": "alta"})
        self.assertIn("sp_demandSignals", conn.cur.sql)
        self.assertEqual(json.loads(conn.cur.args[0]), {"demandSignals": [{"companyId": 1}]})

    def test_sp_error_raises(self):
        conn = _Conn('{"error":"channel does not belong to company"}')
        with mock.patch.object(ds, "connection", return_value=conn):
            with self.assertRaises(RuntimeError):
                ds.record_demand_signal({"demandSignals": [{"companyId": 1}]})


def _check_list(sql: str, column: str) -> set[str]:
    m = re.search(rf"CHECK \({column} IN \(([^)]*)\)\)", sql)
    return set(re.findall(r"'([^']+)'", m.group(1))) if m else set()


class SqlContractTest(unittest.TestCase):
    """The value lists are what the WhatsApp agent sends; the factory once
    replaced them, so they are pinned here."""

    @classmethod
    def setUpClass(cls):
        with open("sql/migrations/2026-11-10_demandSignals.sql", encoding="utf-8") as f:
            cls.table = f.read()
        with open("sql/sp_demandSignals.sql", encoding="utf-8") as f:
            cls.upsert = f.read()

    def test_value_lists(self):
        expected = {
            "concept": {"autoservicio_24h", "lockers", "qr_gmo"},
            "origin": {"anuncio", "organico", "personal"},
            "frequency": {"semanal", "quincenal", "mensual", "ocasional"},
            "preferredTime": {"temprano", "dia", "tarde", "noche", "madrugada", "fin_de_semana"},
            "currentSolution": {"lavadora_propia", "lavanderia", "familiar", "otro"},
            "wouldUse": {"si", "tal_vez", "no"},
            "intentLevel": {"alta", "media", "baja"},
        }
        for column, values in expected.items():
            self.assertEqual(_check_list(self.table, column), values, column)

    def test_timestamps_are_datetime2(self):
        self.assertNotRegex(self.table, r"\bDATETIME\b(?!2)")

    def test_no_delete_and_tenancy_checked(self):
        code = re.sub(r"--.*", "", self.upsert)
        self.assertNotIn("DELETE", code.upper())
        self.assertIn("channel does not belong to company", code)

    def test_reads_mask_the_phone(self):
        # Allowed uses of the raw phone: last 4 digits, the phone-normalizing
        # REPLACE used to match clients, and the full phone ONLY for people who
        # said yes to being contacted (notifyOptIn = 1).
        allowed = (r"RIGHT\(ds\.customerPhone, 4\) AS phoneLast4",
                   r"REPLACE\(ds\.customerPhone,",
                   r"CASE WHEN ds\.notifyOptIn = 1 THEN ds\.customerPhone END AS phone")
        for name in ("sp_demandSignals_all", "sp_demandSignals_one"):
            with open(f"sql/{name}.sql", encoding="utf-8") as f:
                code = re.sub(r"--.*", "", f.read())
            self.assertIn("RIGHT(ds.customerPhone, 4) AS phoneLast4", code, name)
            for pattern in allowed:
                code = re.sub(pattern, "", code)
            self.assertNotIn("customerPhone", code.split("FROM dbo.demandSignals", 1)[0], name)
        with open("sql/sp_demandSignals_zoneSummary.sql", encoding="utf-8") as f:
            output = re.sub(r"--.*", "", f.read()).split("SELECT @zonesJson", 1)[1]
        # The map output only counts phones, never returns them.
        self.assertNotRegex(output, r"(?<!DISTINCT )(?<!THEN )fo\.customerPhone")


if __name__ == "__main__":
    unittest.main()


class ZoneSummaryFunnelTest(unittest.TestCase):
    """The map's funnel top (who came from an ad, who left a zone) returns
    counts only, and doesn't break where dbo.locationHosts isn't deployed."""

    @classmethod
    def setUpClass(cls):
        with open("sql/sp_demandSignals_zoneSummary.sql", encoding="utf-8") as f:
            cls.sql = re.sub(r"--.*", "", f.read())

    def test_funnel_keys_and_counts_only(self):
        tail = self.sql.split("DECLARE @adLeads INT", 1)[1]
        self.assertIn('"funnel":{"adLeads":', tail)
        self.assertIn('"adLeadsWithSignal":', tail)
        self.assertNotRegex(tail, r"customerPhone|contactPhone|p10")

    def test_location_hosts_bound_only_when_deployed(self):
        self.assertIn("IF OBJECT_ID(N'dbo.locationHosts', N'U') IS NOT NULL", self.sql)
        before_guard = self.sql.split("IF OBJECT_ID(N'dbo.locationHosts'", 1)[0]
        self.assertNotIn("dbo.locationHosts", before_guard)
