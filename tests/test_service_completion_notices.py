"""
"Tu servicio está listo" (Dashboard → Actividad Reciente).

Feature switch per company, eligibility, idempotency and the staff-session
guard. The SPs and the dispatcher are mocked (no database, nothing is sent).

Run:  venv/bin/python -m unittest tests/test_service_completion_notices.py -v
"""
import asyncio
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

os.environ.setdefault("SESSION_JWT_SECRET", "t" * 40)

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.serviceCompletionNotices as scn  # noqa: E402
import routes_.serviceCompletionNotices as scn_routes  # noqa: E402
import security.session_tokens as st  # noqa: E402

LAUNDRY, GROCERY = 1, 2
SALES = {  # incomeId -> sale row as sp_income_one returns it
    6112: {"incomeId": 6112, "companyId": LAUNDRY, "clientId": 5417},
    6113: {"incomeId": 6113, "companyId": LAUNDRY, "clientId": 1},       # walk-in
    6114: {"incomeId": 6114, "companyId": LAUNDRY, "clientId": 2049},    # already notified
    7001: {"incomeId": 7001, "companyId": GROCERY, "clientId": 3000},
}


def _income(_cursor, company_id, income_id):
    row = SALES.get(income_id)
    return row if row and row["companyId"] == company_id else None


def _sent(_cursor, _company_id, income_id):
    return {"selectedChannel": "whatsapp", "sentAt": "2026-11-09T10:00:00"} if income_id == 6114 else None


def _features(company_id):
    return dict(scn.DEFAULTS) if company_id == LAUNDRY else None


def _run(coro):
    return asyncio.run(coro)


def _body(resp: JSONResponse) -> dict:
    return json.loads(resp.body)


class ServiceCompletionTest(unittest.TestCase):
    def setUp(self):
        self.dispatch = mock.AsyncMock(return_value=JSONResponse(
            {"status": "sent", "selectedChannel": "whatsapp", "fallbackReason": "NO_DEVICE",
             "attemptedChannels": [{"channel": "push"}, {"channel": "whatsapp"}]}))
        patches = [
            mock.patch.object(scn, "feature_config", side_effect=_features),
            mock.patch.object(scn, "_income", side_effect=_income),
            mock.patch.object(scn, "_sent", side_effect=_sent),
            mock.patch.object(scn, "_client", return_value={"first_name": "Joselin"}),
            mock.patch.object(scn, "company_name", return_value="Lavanderia GMO"),
            mock.patch.object(scn, "connection"),
            mock.patch.object(scn, "log_workflow_step"),
            mock.patch("modules.notificationDispatch.dispatch_notification_connector", self.dispatch),
            mock.patch("modules.income._get_client_phone", return_value="+526620000000"),
        ]
        for p in patches:
            p.start()
        self.addCleanup(mock.patch.stopall)

    def _status(self, company, ids):
        return scn.status({"serviceCompletionNotices": [{"companyId": company, "userId": 9, "incomeIds": ids}]})

    def _send(self, company, income_id):
        return _run(scn.send({"serviceCompletionNotice": [{"companyId": company, "userId": 9, "incomeId": income_id}]}))

    # ── a company without the feature (Abarrotes) ───────────────────────
    def test_feature_off_offers_nothing_and_reads_no_sale(self):
        body = _body(self._status(GROCERY, [7001]))
        self.assertEqual(body, {"enabled": False, "actions": {}})
        scn._income.assert_not_called()

    def test_feature_off_refuses_to_send(self):
        res = self._send(GROCERY, 7001)
        self.assertEqual((res.status_code, _body(res)["error"]), (403, "feature_disabled"))
        self.dispatch.assert_not_awaited()

    # ── Lavandería ──────────────────────────────────────────────────────
    def test_status_lists_only_eligible_sales(self):
        body = _body(self._status(LAUNDRY, [6112, 6113, 6114, 7001, 6112]))
        self.assertTrue(body["enabled"])
        self.assertEqual(body["actions"]["6112"], {"key": scn.ACTION_KEY, "status": "available"})
        self.assertEqual(body["actions"]["6114"]["status"], "sent")
        self.assertNotIn("6113", body["actions"])   # walk-in
        self.assertNotIn("7001", body["actions"])   # another company's sale

    def test_send_goes_through_the_cascade_as_service_completed(self):
        res = self._send(LAUNDRY, 6112)
        self.assertEqual((res.status_code, _body(res)["status"]), (200, "sent"))
        payload = self.dispatch.await_args.args[0]
        self.assertEqual(payload["eventName"], "service_completed")
        self.assertEqual((payload["sourceType"], payload["sourceId"]), ("income", 6112))
        self.assertEqual((payload["recipientType"], payload["recipientId"]), ("client", 5417))
        self.assertEqual(payload["waTemplate"], "servicio_listo")
        self.assertEqual(payload["waParams"], ["Joselin", "Lavanderia GMO"])
        self.assertIn("Tu servicio en Lavanderia GMO está listo", payload["pushMessage"])

    def test_no_phone_or_name_in_the_log(self):
        self._send(LAUNDRY, 6112)
        logged = json.dumps([c.kwargs for c in scn.log_workflow_step.call_args_list])
        self.assertNotIn("6620000000", logged)
        self.assertNotIn("Joselin", logged)

    def test_already_sent_is_not_sent_again(self):
        res = self._send(LAUNDRY, 6114)
        self.assertEqual(_body(res)["status"], "already_sent")
        self.dispatch.assert_not_awaited()

    def test_walk_in_and_foreign_sales_are_refused(self):
        self.assertEqual(self._send(LAUNDRY, 6113).status_code, 409)
        self.assertEqual(self._send(LAUNDRY, 7001).status_code, 404)
        self.dispatch.assert_not_awaited()

    def test_failed_delivery_is_502_and_can_be_retried(self):
        self.dispatch.return_value = JSONResponse({"status": "failed", "fallbackReason": "NO_DEVICE"})
        self.assertEqual(self._send(LAUNDRY, 6112).status_code, 502)
        self.dispatch.return_value = JSONResponse({"status": "sent", "selectedChannel": "sms"})
        self.assertEqual(_body(self._send(LAUNDRY, 6112))["status"], "sent")

    def test_bad_bodies(self):
        self.assertEqual(scn.status({}).status_code, 400)
        self.assertEqual(self._status(LAUNDRY, "6112").status_code, 400)
        self.assertEqual(_run(scn.send({"serviceCompletionNotice": [{"companyId": 1, "userId": 9}]})).status_code, 400)


class FeatureConfigTest(unittest.TestCase):
    def _with_rows(self, rows=None, error=None):
        sp = mock.patch.object(scn, "_sp_rows", side_effect=error) if error else \
            mock.patch.object(scn, "_sp_rows", return_value=rows)
        with sp, mock.patch.object(scn, "connection"):
            return scn.feature_config(LAUNDRY)

    def test_no_row_disabled_row_or_db_error_mean_off(self):
        self.assertIsNone(self._with_rows([]))
        self.assertIsNone(self._with_rows([{"enabled": False, "configJson": ""}]))
        self.assertIsNone(self._with_rows([{"enabled": 0}]))
        self.assertIsNone(self._with_rows(error=RuntimeError("Invalid object name 'dbo.companyFeatures'")))

    def test_enabled_row_merges_its_config_over_defaults(self):
        self.assertEqual(self._with_rows([{"enabled": True, "configJson": ""}]), scn.DEFAULTS)
        cfg = self._with_rows([{"enabled": True, "configJson": '{"pushTitle": "Listo"}'}])
        self.assertEqual((cfg["pushTitle"], cfg["waTemplate"]), ("Listo", "servicio_listo"))
        self.assertEqual(self._with_rows([{"enabled": True, "configJson": "not json"}]), scn.DEFAULTS)

    def test_message(self):
        self.assertEqual(scn.message("", ""), "¡Hola! Tu servicio está listo. Ya puedes pasar por tu pedido. "
                                              "¡Gracias por tu preferencia!")


class RouteGuardTest(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(scn_routes.router)
        self.client = TestClient(app)
        patches = [
            mock.patch.dict(os.environ, {"SESSION_JWT_SECRET": "t" * 40}),
            mock.patch("security.worker_key.WORKER_KEY", "wk"),
            mock.patch.object(scn_routes, "status", return_value=JSONResponse({"enabled": True, "actions": {}})),
        ]
        for p in patches:
            p.start()
        self.addCleanup(mock.patch.stopall)

    def _post(self, token=None, company=LAUNDRY, user=9):
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        return self.client.post("/serviceCompletionNotices/status", headers=headers, json={
            "serviceCompletionNotices": [{"companyId": company, "userId": user, "incomeIds": [6112]}]})

    def test_anonymous_is_refused(self):
        self.assertEqual(self._post().status_code, 403)

    def test_staff_of_the_company_passes(self):
        token = st.issue_session(9, LAUNDRY, 0, "employee")["accessToken"]
        self.assertEqual(self._post(token).status_code, 200)

    def test_other_company_or_other_user_is_refused(self):
        token = st.issue_session(9, GROCERY, 0, "admin")["accessToken"]
        self.assertEqual(self._post(token).status_code, 403)
        token = st.issue_session(10, LAUNDRY, 0, "admin")["accessToken"]
        self.assertEqual(self._post(token).status_code, 403)


if __name__ == "__main__":
    unittest.main()
