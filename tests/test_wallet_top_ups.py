"""
A transfer top-up is credited only by staff who saw the money, and a WhatsApp
comprobante only ever waits for them. No database, Stripe or Meta: all stubbed.

Run:  venv/bin/python -m unittest tests/test_wallet_top_ups.py -v
"""
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.walletTopUps as topups  # noqa: E402
import modules.whatsappEvidence as wa  # noqa: E402
import routes_.walletTopUps as routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402

GOOD = {"companyId": 1, "clientId": 9, "amountMXN": 500, "claveRastreo": "abc123456", "bankFrom": "BBVA",
        "transferDate": "2026-11-05", "evidenceFileUrl": "https://blob/x.jpg", "userId": 3}


class ConfirmTest(unittest.TestCase):
    def setUp(self):
        self.addCleanup(mock.patch.stopall)
        self.entry = mock.patch.object(topups, "post_entry", return_value={"entryId": 5, "balanceAfter": 660}).start()
        self.journal = mock.patch.object(topups, "post_wallet_topup_journal_entry", return_value=True).start()
        self.sp = mock.patch.object(topups, "transfer_evidence_sp",
                                    return_value=JSONResponse({"transferEvidenceId": 7})).start()
        mock.patch.object(topups, "log_workflow_step").start()
        mock.patch.object(topups, "log_audit").start()

    def _confirm(self, **extra):
        response = topups.confirm_transfer({**GOOD, **extra})
        return response.status_code, json.loads(response.body)

    def test_credits_keeps_evidence_and_posts_the_entry(self):
        status, body = self._confirm()
        self.assertEqual(status, 200)
        self.assertEqual(self.entry.call_args.kwargs["idempotency_key"], "transfer:1:ABC123456")
        self.journal.assert_called_once_with(1, 5, 500.0, "2026-11-05", "transferencia")
        self.assertTrue(body["evidenceSaved"] and body["journalPosted"])

    def test_a_repeated_clave_posts_nothing_else(self):
        self.entry.return_value = {"entryId": 5, "replayed": True}
        _, body = self._confirm()
        self.assertTrue(body["replayed"])
        self.journal.assert_not_called()
        self.sp.assert_not_called()

    def test_evidence_is_required(self):
        status, _ = self._confirm(evidenceFileUrl=None)
        self.assertEqual(status, 400)
        self.entry.assert_not_called()

    def test_a_whatsapp_comprobante_is_validated_not_recreated(self):
        self._confirm(transferEvidenceId=7, evidenceFileUrl=None)
        row = self.sp.call_args.args[0]["transferEvidence"][0]
        self.assertEqual((row["action"], row["validationStatus"]), ("validate", "VALID"))

    def test_a_failed_credit_touches_nothing_else(self):
        self.entry.return_value = {"error": "x"}
        status, _ = self._confirm()
        self.assertEqual(status, 400)
        self.journal.assert_not_called()


class TicketTest(unittest.TestCase):
    """Every credit sends the client a ticket once; a replay or a refusal sends none."""

    def setUp(self):
        self.addCleanup(mock.patch.stopall)
        self.entry = mock.patch.object(topups, "post_entry", return_value={"entryId": 5, "balanceAfter": 310}).start()
        mock.patch.object(topups, "post_wallet_topup_journal_entry", return_value=True).start()
        mock.patch.object(topups, "transfer_evidence_sp", return_value=JSONResponse({"transferEvidenceId": 7})).start()
        mock.patch.object(topups, "log_workflow_step").start()
        mock.patch.object(topups, "log_audit").start()
        self.sent = []

    def test_a_confirmed_transfer_sends_one_ticket(self):
        topups.confirm_transfer(GOOD, notify=self.sent.append)
        self.assertEqual(self.sent, [{"companyId": 1, "clientId": 9, "entryId": 5, "amountMXN": 500.0,
                                      "method": "transferencia", "balanceAfter": 310}])

    def test_a_replayed_transfer_sends_none(self):
        self.entry.return_value = {"entryId": 5, "replayed": True}
        topups.confirm_transfer(GOOD, notify=self.sent.append)
        self.assertEqual(self.sent, [])

    def test_cash_credits_with_the_attempt_key_and_sends_a_ticket(self):
        r = topups.credit_cash({"companyId": 1, "clientId": 9, "amountMXN": 50, "userId": 3,
                                "idempotencyKey": "cash:1:9:abc"}, notify=self.sent.append)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self.entry.call_args.kwargs["idempotency_key"], "cash:1:9:abc")
        self.assertEqual(self.sent[0]["method"], "efectivo")

    def test_cash_refuses_a_key_from_another_company(self):
        r = topups.credit_cash({"companyId": 1, "clientId": 9, "amountMXN": 50,
                                "idempotencyKey": "terminal:3:123456"}, notify=self.sent.append)
        self.assertEqual(r.status_code, 400)
        self.entry.assert_not_called()

    def test_terminal_keys_by_operation_and_sends_a_ticket(self):
        r = topups.credit_terminal({"companyId": 1, "clientId": 9, "amountMXN": 150, "terminalId": 3,
                                    "terminalName": "Terminal MP", "operationNumber": "abc-1234"},
                                   notify=self.sent.append)
        self.assertEqual(r.status_code, 200)
        kwargs = self.entry.call_args.kwargs
        self.assertEqual((kwargs["idempotency_key"], kwargs["reference_type"], kwargs["reference_id"]),
                         ("terminal:3:ABC-1234", "commissionTerminal", 3))
        self.assertEqual(self.sent[0]["method"], "terminal")

    def test_terminal_refuses_a_bad_operation_number(self):
        r = topups.credit_terminal({"companyId": 1, "clientId": 9, "amountMXN": 150, "terminalId": 3,
                                    "operationNumber": "x"}, notify=self.sent.append)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self.sent, [])

    def test_the_ticket_reads_like_a_receipt(self):
        text = topups.top_up_message({"amountMXN": 50, "method": "transferencia", "companyName": "Lavanderia GMO",
                                      "balanceAfter": 310, "entryId": 1234})
        self.assertEqual(text, "Abono de $50.00 MXN con transferencia en Lavanderia GMO.\n"
                               "Saldo disponible: $310.00 MXN\nFolio: 1234")

    def test_the_ticket_goes_through_the_push_whatsapp_sms_cascade(self):
        import asyncio
        import modules.notificationDispatch as dispatch
        with mock.patch.object(topups, "company_name", return_value="Lavanderia GMO"), \
             mock.patch.object(topups, "_client_phone", return_value="+526621806214"), \
             mock.patch.object(dispatch, "dispatch_notification_connector",
                               new=mock.AsyncMock(return_value=JSONResponse({}))) as send:
            asyncio.run(topups.notify_top_up({"companyId": 1, "clientId": 9, "entryId": 5, "amountMXN": 50,
                                              "method": "efectivo", "balanceAfter": 310}))
        payload = send.call_args.args[0]
        self.assertEqual((payload["eventName"], payload["sourceType"], payload["sourceId"], payload["waTemplate"]),
                         ("wallet_topup_credited", "walletTransaction", 5, "abono_saldo"))
        self.assertEqual(payload["navigationRoute"], "/my-qr")

    def test_a_failed_ticket_never_raises(self):
        with mock.patch.object(topups, "company_name", side_effect=RuntimeError("db down")):
            import asyncio
            asyncio.run(topups.notify_top_up({"companyId": 1, "clientId": 9, "entryId": 5}))


class RouteTest(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(routes.router)
        self.client = TestClient(app)
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(worker_key, "WORKER_KEY", "key").start()

    def _post(self, claims):
        with mock.patch.object(routes, "decode", return_value=claims), \
             mock.patch.object(routes, "confirm_transfer", return_value=JSONResponse({"ok": 1})):
            return self.client.post("/walletTopUps/transfer/confirm", json=GOOD,
                                    headers={"Authorization": "Bearer t"}).status_code

    def test_no_session_or_key_is_refused(self):
        self.assertEqual(self.client.post("/walletTopUps/transfer/confirm", json=GOOD).status_code, 403)

    def test_a_client_session_cannot_credit_itself(self):
        self.assertEqual(self._post({"sub": "3", "companies": [{"companyId": 1, "role": "pos"}]}), 403)

    def test_staff_of_another_company_is_refused(self):
        self.assertEqual(self._post({"sub": "3", "companies": [{"companyId": 2, "role": "admin"}]}), 403)

    def test_staff_of_the_company_gets_through(self):
        self.assertEqual(self._post({"sub": "3", "companies": [{"companyId": 1, "role": "employee"}]}), 200)

    def test_cash_and_terminal_need_staff_too(self):
        for path in ("/walletTopUps/cash", "/walletTopUps/terminal"):
            self.assertEqual(self.client.post(path, json=GOOD).status_code, 403)
            with mock.patch.object(routes, "decode", return_value={"sub": "3", "companies": [
                    {"companyId": 1, "role": "pos"}]}):
                self.assertEqual(self.client.post(path, json=GOOD, headers={"Authorization": "Bearer t"}).status_code,
                                 403)


class WhatsAppTest(unittest.TestCase):
    CHANNEL = {"companyId": 1, "channelId": 2}
    READING = {"isTransferReceipt": True, "amountMXN": 500, "claveRastreo": "ABC123456",
               "transferDate": "2026-11-05", "bankFrom": "BBVA"}

    def setUp(self):
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(wa, "AGENT_URL", "http://agent").start()
        mock.patch.object(wa, "_download", return_value=b"img").start()
        self.read = mock.patch.object(wa, "_read", return_value=self.READING).start()
        self.lookup = mock.patch.object(wa, "assistant_sp", return_value={
            "result": [{"status": "found", "clientId": 9}]}).start()
        mock.patch.object(wa, "_upload_base64_to_blob", return_value="https://blob/x.jpg").start()
        self.create = mock.patch.object(wa, "create_pending_evidence", return_value={"transferEvidenceId": 7}).start()
        self.push = mock.patch.object(wa, "_push_staff").start()
        mock.patch.object(wa, "log_workflow_step").start()

    def _handle(self):
        return wa.handle_image(self.CHANNEL, "+526620000000", "media1")

    def test_a_receipt_waits_for_staff_and_pushes_them(self):
        self.assertIn("$500.00", self._handle())
        self.assertEqual(self.create.call_args.args[0]["clientId"], 9)
        self.push.assert_called_once_with(self.CHANNEL, 9, 500.0)

    def test_other_photos_go_to_the_normal_agent(self):
        self.read.return_value = {"isTransferReceipt": False}
        self.assertIsNone(self._handle())
        self.create.assert_not_called()

    def test_an_unreadable_receipt_asks_for_another_photo(self):
        self.read.return_value = {**self.READING, "claveRastreo": ""}
        self.assertEqual(self._handle(), wa._UNREADABLE)
        self.create.assert_not_called()

    def test_an_unknown_number_saves_nothing(self):
        self.lookup.return_value = {"result": [{"status": "not_found"}]}
        self.assertEqual(self._handle(), wa._NOT_REGISTERED)
        self.create.assert_not_called()

    def test_the_same_comprobante_twice_is_answered_kindly(self):
        self.create.return_value = {"error": "UQ_transferEvidence_claveRastreo violated"}
        self.assertEqual(self._handle(), wa._DUPLICATE)
        self.push.assert_not_called()


if __name__ == "__main__":
    unittest.main()
