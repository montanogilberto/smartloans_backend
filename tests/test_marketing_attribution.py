"""
Client Acquisition, phase 1: the ad behind each WhatsApp lead.

Meta sends messages[].referral only on the first message after a click, so the
webhook must save it, and a failure there must never cost the customer a reply.
No database / no Meta / no agent: everything external is stubbed. The SQL tests
read the scripts as text: they pin the rules down, they do not execute them.

Run:  venv/bin/python -m unittest tests/test_marketing_attribution.py -v
"""
import json
import os
import re
import sys
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from fastapi import FastAPI  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.marketingLeadAttributions as mla  # noqa: E402
import modules.whatsappCloud as wc  # noqa: E402
import observability.logger as obs_logger  # noqa: E402
import routes_.marketingLeadAttribution as mla_routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402

KEY = "test-worker-key"
LAUNDRY = {"channelId": 2, "companyId": 1, "branchId": None, "phoneNumberId": "111", "botEnabled": True}
OTHER = {"channelId": 9, "companyId": 2, "branchId": 4, "phoneNumberId": "222", "botEnabled": True}
CHANNELS = {"111": LAUNDRY, "222": OTHER}

REFERRAL = {
    "source_type": "ad",
    "source_id": "120210000000001",
    "source_url": "https://fb.me/abc",
    "headline": "Lavandería GMO",
    "body": "Tu primera carga con descuento",
    "media_type": "image",
    "ctwa_clid": "ARAkLkA8rmlFeiCktEJQ",
}


def _message(msg_type="text", referral=REFERRAL, wamid="wamid.A", sender="5216621234567", **extra):
    msg = {"from": sender, "id": wamid, "timestamp": "1762300000", "type": msg_type, **extra}
    if msg_type == "text":
        msg.setdefault("text", {"body": "Hola"})
    if referral is not None:
        msg["referral"] = referral
    return msg


def _payload(*messages, phone_number_id="111"):
    return {"entry": [{"changes": [{"field": "messages", "value": {
        "metadata": {"phone_number_id": phone_number_id},
        "contacts": [{"wa_id": "5216621234567", "profile": {"name": "Ana"}}],
        "messages": list(messages),
    }}]}]}


def _sql(name):
    with open(os.path.join(ROOT, "sql", name), encoding="utf-8") as f:
        return f.read()


class ExtractReferralTest(unittest.TestCase):
    def _extract(self, msg):
        return wc._extract_inbound(_payload(msg))[0]

    def test_text_message_keeps_the_whole_referral(self):
        self.assertEqual(self._extract(_message())["referral"], REFERRAL)

    def test_non_text_first_messages_keep_it_too(self):
        cases = [
            _message("image", image={"id": "m1"}),
            _message("audio", audio={"id": "m2"}),
            _message("button", button={"text": "Quiero info"}),
            _message("interactive", interactive={"button_reply": {"title": "Precios"}}),
        ]
        for msg in cases:
            with self.subTest(type=msg["type"]):
                self.assertEqual(self._extract(msg)["referral"], REFERRAL)

    def test_a_message_without_an_ad_has_no_referral(self):
        self.assertIsNone(self._extract(_message(referral=None))["referral"])

    def test_each_message_of_a_batch_keeps_its_own(self):
        out = wc._extract_inbound(_payload(_message(wamid="a"), _message(wamid="b", referral=None)))
        self.assertEqual([m["referral"] for m in out], [REFERRAL, None])


class WebhookStubs(unittest.TestCase):
    def setUp(self):
        wc._seen_messages.clear()  # each test is a new delivery
        self.calls = []
        self.record = mock.Mock(side_effect=lambda *_: self.calls.append("record") or 1)
        self.reply_to = mock.Mock(side_effect=lambda *a, **k: self.calls.append("agent") or "¡Hola!")
        self.send_text = mock.Mock()
        patches = [
            mock.patch.object(wc.whatsappChannels, "get_channel", side_effect=CHANNELS.get),
            mock.patch.object(wc.marketingLeadAttributions, "record_referral", self.record),
            mock.patch.object(wc.marketingAds, "ensure_pending", return_value=1),
            mock.patch.object(wc.clientContactPreferences, "handle_keyword", return_value=None),
            mock.patch.object(wc.whatsappReservations, "reply_to", self.reply_to),
            mock.patch.object(wc, "log_message_to_database"),
            mock.patch.object(wc, "send_text", self.send_text),
        ]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def _row(self, call=0):
        return self.record.call_args_list[call].args[0]["marketingLeadAttributions"][0]


class WebhookCaptureTest(WebhookStubs):
    def test_saves_the_ad_data_with_a_normalized_phone(self):
        wc.handle_webhook(_payload(_message()))
        row = self._row()
        self.assertEqual(row["action"], 1)
        self.assertEqual(row["provider"], "meta")
        self.assertEqual(row["conversionChannel"], "whatsapp")
        self.assertEqual(row["channelId"], 2)
        self.assertEqual(row["customerPhone"], "+526621234567")  # Meta's legacy 521 is gone
        self.assertEqual(row["sourceId"], REFERRAL["source_id"])
        self.assertEqual(row["ctwaClid"], REFERRAL["ctwa_clid"])
        self.assertEqual(row["rawReferral"], REFERRAL)
        self.assertEqual(row["referredAt"], "2025-11-04T23:46:40")

    def test_non_text_first_message_is_saved(self):
        wc.handle_webhook(_payload(_message("image", image={"id": "m1"})))
        self.assertEqual(self.record.call_count, 1)

    def test_no_referral_writes_nothing(self):
        wc.handle_webhook(_payload(_message(referral=None)))
        self.record.assert_not_called()
        self.send_text.assert_called_once()

    def test_saved_before_the_agent_runs(self):
        # The agent creates the conversation row isNewLead looks for.
        wc.handle_webhook(_payload(_message()))
        self.assertEqual(self.calls, ["record", "agent"])

    def test_a_failed_save_still_answers_the_customer(self):
        self.record.side_effect = RuntimeError("db down")
        wc.handle_webhook(_payload(_message()))
        self.send_text.assert_called_once()

    def test_a_malformed_referral_still_answers_the_customer(self):
        wc.handle_webhook(_payload(_message(referral="not-an-object")))
        self.record.assert_not_called()
        self.send_text.assert_called_once()

    def test_missing_fields_become_none_and_long_ones_are_cut(self):
        wc.handle_webhook(_payload(_message(referral={"source_id": "1", "headline": "x" * 300})))
        row = self._row()
        self.assertEqual(len(row["headline"]), 255)
        for field in ("body", "sourceUrl", "mediaType", "sourceType", "ctwaClid"):
            self.assertIsNone(row[field], field)

    def test_a_bad_timestamp_is_left_for_the_sp_to_fill(self):
        msg = _message()
        msg["timestamp"] = "not-a-number"
        wc.handle_webhook(_payload(msg))
        self.assertIsNone(self._row()["referredAt"])

    def test_unregistered_number_is_not_recorded(self):
        wc.handle_webhook(_payload(_message(), phone_number_id="999"))
        self.record.assert_not_called()

    def test_opt_out_keyword_is_still_recorded_and_still_answered(self):
        with mock.patch.object(wc.clientContactPreferences, "handle_keyword", return_value="Listo"):
            wc.handle_webhook(_payload(_message()))
        self.assertEqual(self.record.call_count, 1)
        self.reply_to.assert_not_called()
        self.send_text.assert_called_once()


class IdempotencyTest(WebhookStubs):
    def test_a_meta_retry_sends_the_same_event_id(self):
        payload = _payload(_message(wamid="wamid.RETRY"))
        wc.handle_webhook(payload)
        wc.handle_webhook(payload)
        self.assertEqual(self._row(0)["externalEventId"], "wamid.RETRY")
        self.assertEqual(self._row(1)["externalEventId"], "wamid.RETRY")

    def test_two_clicks_are_two_events(self):
        wc.handle_webhook(_payload(_message(wamid="a"), _message(wamid="b")))
        self.assertEqual([self._row(i)["externalEventId"] for i in (0, 1)], ["a", "b"])

    def test_sp_dedupes_on_company_provider_and_event(self):
        sql = re.sub(r"\s+", " ", _sql("sp_marketingLeadAttributions.sql"))
        self.assertIn("WITH (UPDLOCK, HOLDLOCK) WHERE companyId = @companyId AND provider = @provider "
                      "AND externalEventId = @externalEventId", sql)
        self.assertIn("IN (2627, 2601)", sql)  # two workers racing: return the row, not an error

    def test_table_enforces_it_too(self):
        sql = _sql("migrations/2026-11-04_marketingLeadAttributions.sql")
        self.assertRegex(sql, r"UNIQUE NONCLUSTERED \(companyId, provider, externalEventId\)")


class CompanyIsolationTest(WebhookStubs):
    def test_company_comes_from_the_channel_never_the_ad(self):
        forged = {**REFERRAL, "companyId": 2, "company_id": 2}
        wc.handle_webhook(_payload(_message(referral=forged)))
        self.assertEqual(self._row()["companyId"], 1)

    def test_same_person_on_two_companies_stays_separate(self):
        wc.handle_webhook(_payload(_message(wamid="a"), phone_number_id="111"))
        wc.handle_webhook(_payload(_message(wamid="b"), phone_number_id="222"))
        self.assertEqual([(self._row(i)["companyId"], self._row(i)["channelId"]) for i in (0, 1)],
                         [(1, 2), (2, 9)])

    def test_sp_refuses_a_channel_of_another_company(self):
        sql = _sql("sp_marketingLeadAttributions.sql")
        self.assertIn("channelId = @channelId AND companyId = @companyId", sql)
        self.assertIn("channel_not_in_company", sql)

    def test_client_match_and_lead_checks_stay_in_the_company(self):
        sql = _sql("sp_marketingLeadAttributions.sql")
        self.assertIn("AND c.companyId = @companyId", sql)
        self.assertIn("wch.companyId = @companyId", sql)
        self.assertIn("mla.companyId = @companyId", sql)

    def test_reads_are_scoped_to_the_company(self):
        self.assertIn("WHERE companyId = @companyId", _sql("sp_marketingLeadAttributions_all.sql"))
        self.assertIn("marketingLeadAttributionId = @id AND companyId = @companyId",
                      _sql("sp_marketingLeadAttributions_one.sql"))
        self.assertIn("companyId is required", _sql("sp_marketingLeadAttributions_all.sql"))


class DuplicatePhoneMatchingTest(unittest.TestCase):
    def setUp(self):
        self.sql = re.sub(r"\s+", " ", _sql("sp_marketingLeadAttributions.sql"))

    def test_the_same_client_wins_every_time(self):
        self.assertRegex(self.sql, r"SELECT TOP 1 @resolvedClientId = c\.clientId .*? ORDER BY c\.clientId;")

    def test_matches_on_the_last_ten_digits(self):
        self.assertIn("RIGHT(REPLACE(REPLACE(REPLACE(c.cellphone,'+',''),' ',''),'-',''),10) = @normalizedCustomerPhone",
                      self.sql)

    def test_the_placeholder_client_is_never_matched(self):
        self.assertIn("ISNULL(c.first_name, N'') <> N'Desconocido'", self.sql)


class NoPosClientCreationTest(unittest.TestCase):
    def test_the_sp_never_writes_clients(self):
        sql = _sql("sp_marketingLeadAttributions.sql")
        self.assertNotRegex(sql, r"(?i)(INSERT\s+INTO|UPDATE|DELETE\s+FROM|MERGE)\s+(\[?dbo\]?\.)?\[?clients\b")

    def test_the_module_calls_no_client_procedure(self):
        with open(mla.__file__, encoding="utf-8") as f:
            self.assertNotIn("sp_clients", f.read())

    def test_the_only_sp_run_for_a_click_is_the_attribution_one(self):
        conn = _FakeConnection([_ok()])
        with mock.patch.object(mla, "connection", return_value=conn):
            mla.record_referral({"marketingLeadAttributions": [{"action": 1}]})
        self.assertEqual(len(conn.statements), 1)
        self.assertIn("sp_marketingLeadAttributions", conn.statements[0][0])


class _FakeCursor:
    def __init__(self, conn):
        self.conn = conn

    def execute(self, sql, params=()):
        self.conn.statements.append((sql, params))

    def fetchone(self):
        return self.conn.rows[0]

    def fetchall(self):
        return self.conn.rows


class _FakeConnection:
    def __init__(self, results):
        self.rows = results[0]
        self.statements = []
        self.closed = False

    def cursor(self):
        return _FakeCursor(self)

    def close(self):
        self.closed = True


def _ok(row_id=7):
    return [(json.dumps({"result": [{"marketingLeadAttributions": [{"marketingLeadAttributionId": row_id}]}]}),)]


class RecordReferralTest(unittest.TestCase):
    PAYLOAD = {"marketingLeadAttributions": [{"action": 1, "rawReferral": REFERRAL, "clientId": None}]}

    def _run(self, rows):
        self.conn = _FakeConnection([rows])
        with mock.patch.object(mla, "connection", return_value=self.conn):
            return mla.record_referral(self.PAYLOAD)

    def test_returns_the_row_id_and_closes_the_connection(self):
        self.assertEqual(self._run(_ok(7)), 7)
        self.assertTrue(self.conn.closed)

    def test_sends_the_referral_as_a_json_object_and_keeps_nulls(self):
        self._run(_ok())
        sql, params = self.conn.statements[0]
        self.assertEqual(sql, "EXEC [dbo].[sp_marketingLeadAttributions] @pjsonfile = %s")
        sent = json.loads(params[0])["marketingLeadAttributions"][0]
        self.assertEqual(sent["rawReferral"], REFERRAL)
        self.assertIsNone(sent["clientId"])

    def test_an_sp_error_raises_and_closes_the_connection(self):
        with self.assertRaisesRegex(RuntimeError, "channel_not_in_company"):
            self._run([('{"error":"channel_not_in_company"}',)])
        self.assertTrue(self.conn.closed)


class ObservabilityTest(unittest.TestCase):
    def _record(self, rows):
        conn = _FakeConnection([rows])
        with mock.patch.object(mla, "connection", return_value=conn):
            return mla.record_referral({"marketingLeadAttributions": [{"action": 1}]})

    def test_a_save_logs_success(self):
        with mock.patch.object(obs_logger, "log_workflow_step") as log:
            self._record(_ok())
        self.assertEqual(log.call_args.kwargs["status"], "SUCCESS")
        self.assertEqual(log.call_args.kwargs["workflow_name"], "marketing_attribution")

    def test_an_sp_error_logs_failed_not_success(self):
        with mock.patch.object(obs_logger, "log_workflow_step") as log:
            with self.assertRaises(RuntimeError):
                self._record([('{"error":"boom"}',)])
        self.assertEqual([c.kwargs["status"] for c in log.call_args_list], ["FAILED"])

    def test_a_broken_log_writer_does_not_fail_a_saved_click(self):
        with mock.patch.object(obs_logger.writer, "enqueue", side_effect=RuntimeError("log down")):
            self.assertEqual(self._record(_ok(7)), 7)

    def test_a_broken_log_writer_does_not_hide_a_real_error(self):
        with mock.patch.object(obs_logger.writer, "enqueue", side_effect=RuntimeError("log down")):
            with self.assertRaisesRegex(RuntimeError, "boom"):
                self._record([('{"error":"boom"}',)])


class ReadRoutesTest(unittest.TestCase):
    ROUTES = ("/all_marketingLeadAttributions", "/one_marketingLeadAttributions")
    BODY = {"marketingLeadAttributions": [{"companyId": 1, "marketingLeadAttributionId": 1}]}

    def setUp(self):
        app = FastAPI()
        app.include_router(mla_routes.router)
        self.client = TestClient(app)
        p = mock.patch.object(worker_key, "WORKER_KEY", KEY)
        p.start()
        self.addCleanup(p.stop)

    def _post(self, route, rows=None, **headers):
        conn = _FakeConnection([rows or [('{"result":[{"marketingLeadAttributions":[]}]}',)]])
        with mock.patch.object(mla, "connection", return_value=conn):
            response = self.client.post(route, json=self.BODY, headers=headers)
        return response, conn

    def test_no_key_never_reaches_the_database(self):
        for route in self.ROUTES:
            with self.subTest(route=route):
                response, conn = self._post(route)
                self.assertEqual(response.status_code, 403)
                self.assertEqual(conn.statements, [])

    def test_a_wrong_key_is_refused(self):
        for route in self.ROUTES:
            with self.subTest(route=route):
                self.assertEqual(self._post(route, **{"X-Worker-Key": "nope"})[0].status_code, 403)

    def test_an_unset_server_key_refuses_everyone(self):
        with mock.patch.object(worker_key, "WORKER_KEY", ""):
            for route in self.ROUTES:
                with self.subTest(route=route):
                    self.assertEqual(self._post(route, **{"X-Worker-Key": ""})[0].status_code, 403)

    def test_the_right_key_gets_through(self):
        for route in self.ROUTES:
            with self.subTest(route=route):
                self.assertEqual(self._post(route, **{"X-Worker-Key": KEY})[0].status_code, 200)

    def test_there_is_no_public_create_route(self):
        paths = {r.path for r in mla_routes.router.routes}
        self.assertEqual(paths, set(self.ROUTES))

    def test_null_stays_null(self):
        rows = [('{"result":[{"marketingLeadAttributions":[{"clientId":null,"sourceId":null}]}]}',)]
        response, _ = self._post(self.ROUTES[0], rows, **{"X-Worker-Key": KEY})
        row = response.json()["result"][0]["marketingLeadAttributions"][0]
        self.assertIsNone(row["clientId"])
        self.assertIsNone(row["sourceId"])

    def test_json_split_across_rows_is_joined(self):
        rows = [('{"result":[{"marketingLead',), ('Attributions":[]}]}',)]
        response, _ = self._post(self.ROUTES[0], rows, **{"X-Worker-Key": KEY})
        self.assertEqual(response.json(), {"result": [{"marketingLeadAttributions": []}]})


class SqlRulesTest(unittest.TestCase):
    """Text checks only: nothing here proves the SQL runs."""

    def test_raw_referral_is_read_as_an_object(self):
        self.assertIn("JSON_QUERY(value, '$.rawReferral')", _sql("sp_marketingLeadAttributions.sql"))

    def test_missing_date_falls_back_to_server_time(self):
        self.assertIn("ISNULL(@referredAt, SYSUTCDATETIME())", _sql("sp_marketingLeadAttributions.sql"))

    def test_missing_or_unknown_action_is_rejected(self):
        sql = _sql("sp_marketingLeadAttributions.sql")
        self.assertIn("ISNULL(@action, 0) <> 1", sql)
        self.assertIn("unsupported_action", sql)

    def test_dates_are_datetime2(self):
        sql = _sql("migrations/2026-11-04_marketingLeadAttributions.sql")
        self.assertNotRegex(sql, r"\bDATETIME\b(?!2)")

    def test_reads_keep_nulls(self):
        for name in ("sp_marketingLeadAttributions_all.sql", "sp_marketingLeadAttributions_one.sql"):
            with self.subTest(sp=name):
                self.assertIn("INCLUDE_NULL_VALUES", _sql(name))

    def test_the_click_id_never_leaves_through_a_read(self):
        list_sql = _sql("sp_marketingLeadAttributions_all.sql").split("AS\nBEGIN", 1)[1]
        self.assertNotIn("ctwaClid", list_sql)
        self.assertNotIn("rawReferral", list_sql)
        one_sql = _sql("sp_marketingLeadAttributions_one.sql").split("AS\nBEGIN", 1)[1]
        self.assertNotIn("ctwaClid", one_sql)
        self.assertIn("JSON_MODIFY(rawReferral, '$.ctwa_clid', NULL)", one_sql)


if __name__ == "__main__":
    unittest.main()
