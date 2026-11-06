"""
Who may change the data the WhatsApp agent gives customers.

Nothing here reaches the database: the SP helpers are mocked.

Run:  venv/bin/python -m unittest tests/test_config_write_auth.py -v
"""
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import routes_.reservations as reservation_routes  # noqa: E402
import routes_.whatsappAssistant as assistant_routes  # noqa: E402
import routes_.whatsappCloud as cloud_routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402
from security import session_tokens  # noqa: E402

SECRET = "s" * 40
KEY = "test-worker-key"
COMPANY = 77

app = FastAPI()
app.include_router(assistant_routes.router)
app.include_router(reservation_routes.router)
app.include_router(cloud_routes.router)
client = TestClient(app)

CATALOGS = {
    "/businessInfo": "businessInfo",
    "/businessFaqs": "businessFaqs",
    "/promotions": "promotions",
    "/reservationServices": "reservationServices",
    "/reservationHours": "reservationHours",
}


def bearer(role="admin", company=COMPANY):
    token = session_tokens.issue_session(7, company, 21, role)["accessToken"]
    return {"Authorization": f"Bearer {token}"}


class ConfigWriteAuth(unittest.TestCase):
    def setUp(self):
        ok = JSONResponse({"result": []})
        for patcher in (
            mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": SECRET}),
            mock.patch.object(worker_key, "WORKER_KEY", KEY),
            mock.patch.object(assistant_routes, "assistant_catalog_sp", return_value=ok),
            mock.patch.object(reservation_routes, "reservation_catalog_sp", return_value=ok),
            mock.patch.object(cloud_routes, "whatsapp_channels_sp", return_value=ok),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def post(self, path, row, headers=None):
        return client.post(path, json={CATALOGS[path]: [row]}, headers=headers or {}).status_code

    def each_catalog(self):
        for path in CATALOGS:
            with self.subTest(path=path):
                yield path

    def test_reads_stay_open(self):
        for path in self.each_catalog():
            self.assertEqual(self.post(path, {"companyId": COMPANY}), 200)
            self.assertEqual(self.post(path, {"action": 0, "companyId": COMPANY}), 200)

    def test_anonymous_write_is_refused(self):
        for path in self.each_catalog():
            self.assertEqual(self.post(path, {"action": 1, "companyId": COMPANY}), 403)

    def test_action_sent_as_text_is_still_a_write(self):
        self.assertEqual(self.post("/businessInfo", {"action": "1", "companyId": COMPANY}), 403)

    def test_a_write_hidden_behind_a_read_row_is_refused(self):
        body = {"businessInfo": [{"companyId": COMPANY}, {"action": 1, "companyId": COMPANY}]}
        self.assertEqual(client.post("/businessInfo", json=body).status_code, 403)

    def test_body_that_is_not_a_list_of_rows_is_refused(self):
        for body in ({"businessInfo": {"action": 1}}, {"businessInfo": []}, {}):
            with self.subTest(body=body):
                self.assertEqual(client.post("/businessInfo", json=body).status_code, 403)

    def test_admin_and_manager_of_the_company_can_write(self):
        for role in ("admin", "manager", "Admin"):
            for path in self.each_catalog():
                self.assertEqual(self.post(path, {"action": 1, "companyId": COMPANY}, bearer(role)), 200)

    def test_other_roles_cannot_write(self):
        for role in ("employee", "pos", "borrower", "lender", ""):
            with self.subTest(role=role):
                self.assertEqual(self.post("/businessInfo", {"action": 1, "companyId": COMPANY}, bearer(role)), 403)

    def test_admin_of_another_company_cannot_write(self):
        self.assertEqual(self.post("/businessInfo", {"action": 1, "companyId": COMPANY}, bearer(company=78)), 403)

    def test_x_company_id_header_gives_no_access(self):
        headers = {**bearer(company=78), "X-Company-Id": str(COMPANY)}
        self.assertEqual(self.post("/businessInfo", {"action": 1, "companyId": COMPANY}, headers), 403)

    def test_write_without_company_is_refused(self):
        self.assertEqual(self.post("/businessInfo", {"action": 1}, bearer()), 403)

    def test_expired_or_forged_token_gets_401_so_the_app_refreshes(self):
        headers = {"Authorization": "Bearer not-a-token"}
        self.assertEqual(self.post("/businessInfo", {"action": 1, "companyId": COMPANY}, headers), 401)

    def test_refresh_token_cannot_write(self):
        token = session_tokens.issue_session(7, COMPANY, 21, "admin")["refreshToken"]
        headers = {"Authorization": f"Bearer {token}"}
        self.assertEqual(self.post("/businessInfo", {"action": 1, "companyId": COMPANY}, headers), 401)

    def test_worker_key_can_write(self):
        headers = {"X-Worker-Key": KEY}
        self.assertEqual(self.post("/businessInfo", {"action": 1, "companyId": COMPANY}, headers), 200)

    def test_wrong_worker_key_is_refused(self):
        headers = {"X-Worker-Key": "wrong"}
        self.assertEqual(self.post("/businessInfo", {"action": 1, "companyId": COMPANY}, headers), 403)

    def test_channels_need_the_worker_key_even_to_read(self):
        body = {"whatsappChannels": [{"companyId": COMPANY}]}
        self.assertEqual(client.post("/whatsapp/channels", json=body).status_code, 403)
        self.assertEqual(client.post("/whatsapp/channels", json=body, headers=bearer()).status_code, 403)
        self.assertEqual(client.post("/whatsapp/channels", json=body, headers={"X-Worker-Key": KEY}).status_code, 200)


if __name__ == "__main__":
    unittest.main()
