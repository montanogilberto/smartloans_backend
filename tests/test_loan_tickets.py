"""RFC-014 phase 1: a ticket for funding DECLARED and CONFIRMED, to both parties,
through notificationDispatch (push -> WhatsApp -> SMS) + email, with a signed
/comprobante link rendered on open."""
import asyncio
import json
import os
import unittest
from unittest import mock

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.testclient import TestClient

from modules import fundingTransactions, loanTickets
from routes_ import loanTickets as loan_tickets_routes

SECRET = {"LOAN_TICKET_LINK_SECRET": "test-secret-long-random", "BACKEND_PUBLIC_URL": "https://api.test"}
FT = {"fundingTransactionId": 41, "loanId": 88, "lenderClientId": 3371, "borrowerClientId": 2165,
      "amountMXN": 5000, "transferDate": "2026-11-19T18:00:00", "status": "PENDING_CONFIRMATION",
      "declaredAt": "2026-11-19T18:05:00"}
CONTACTS = {3371: {"email": "lender@test.mx", "phone": "+526620000001", "name": "Jose"},
            2165: {"email": "", "phone": "+526620000002", "name": "Ana"}}


class TicketLinkTests(unittest.TestCase):
    def test_roundtrip(self):
        with mock.patch.dict(os.environ, SECRET):
            link = loanTickets.ticket_link(1008, "funding", 41, "lender")
            self.assertTrue(link.startswith("https://api.test/comprobante/1008-funding-41-lender-"))
            self.assertEqual(loanTickets.verify_token(link.rsplit("/", 1)[1]), (1008, "funding", 41, "lender"))

    def test_link_of_one_party_does_not_open_as_the_other(self):
        with mock.patch.dict(os.environ, SECRET):
            token = loanTickets.ticket_link(1008, "funding", 41, "lender").rsplit("/", 1)[1]
            self.assertIsNone(loanTickets.verify_token(token.replace("-lender-", "-borrower-")))

    def test_tampered_or_counted_ids_are_rejected(self):
        with mock.patch.dict(os.environ, SECRET):
            token = loanTickets.ticket_link(1008, "funding", 41, "lender").rsplit("/", 1)[1]
            self.assertIsNone(loanTickets.verify_token(token.replace("-41-", "-42-")))
            self.assertIsNone(loanTickets.verify_token("garbage"))

    def test_fails_closed_without_secret(self):
        with mock.patch.dict(os.environ, SECRET):
            token = loanTickets.ticket_link(1008, "funding", 41, "lender").rsplit("/", 1)[1]
        with mock.patch.dict(os.environ, {"LOAN_TICKET_LINK_SECRET": ""}):
            self.assertIsNone(loanTickets.ticket_link(1008, "funding", 41, "lender"))
            self.assertIsNone(loanTickets.verify_token(token))


class NotifyFundingTests(unittest.TestCase):
    with_app: set = set()

    def run_notify(self, event, loan_status=None, dispatch_side_effect=None, with_app=()):
        self.dispatched, self.emails = [], []
        self.with_app = set(with_app)
        with mock.patch.dict(os.environ, SECRET), \
                mock.patch.object(loanTickets, "_funding_one", return_value=dict(FT)), \
                mock.patch.object(loanTickets, "_contact", side_effect=lambda cid: CONTACTS[cid]), \
                mock.patch.object(loanTickets, "_dispatch",
                                  side_effect=dispatch_side_effect or self.dispatched.append), \
                mock.patch.object(loanTickets, "_has_app", side_effect=lambda cid: cid in self.with_app), \
                mock.patch.object(loanTickets, "_email",
                                  side_effect=lambda c, t, d, l, f: self.emails.append((c["email"], t, l))):
            loanTickets.notify_funding_event(1008, 41, event, loan_status)

    def test_declared_goes_to_both_parties_with_their_own_event(self):
        self.run_notify("declared")
        by_event = {p["eventName"]: p for p in self.dispatched}
        self.assertEqual(set(by_event), {"funding_declared_lender", "funding_declared_borrower"})
        self.assertEqual(by_event["funding_declared_lender"]["recipientId"], 3371)
        self.assertEqual(by_event["funding_declared_borrower"]["recipientId"], 2165)
        for p in self.dispatched:
            self.assertEqual(p["recipientType"], "client")  # dispatcher resolves clientId -> userId
            self.assertEqual(p["sourceType"], "fundingTransaction")
            self.assertEqual(p["sourceId"], 41)
            self.assertEqual(p["waTemplate"], "comprobante_listo")
            self.assertEqual(p["navigationRoute"], "/loan-detail/88")
            self.assertIn("/comprobante/1008-funding-41-", p["receiptUrl"])
            self.assertEqual(p["waParams"][1], p["receiptUrl"])
        self.assertIn("Confirma tu fondeo", by_event["funding_declared_borrower"]["pushTitle"])
        self.assertIn("$5,000.00 MXN", by_event["funding_declared_lender"]["pushMessage"])

    def test_each_party_gets_a_link_signed_for_them(self):
        self.run_notify("declared")
        links = {p["eventName"]: p["receiptUrl"] for p in self.dispatched}
        self.assertIn("-lender-", links["funding_declared_lender"])
        self.assertIn("-borrower-", links["funding_declared_borrower"])

    def test_confirmed_active_says_prestamo_activo(self):
        self.run_notify("confirmed", "active")
        self.assertEqual({p["pushTitle"] for p in self.dispatched}, {"Préstamo activo"})
        self.assertEqual({p["eventName"] for p in self.dispatched},
                         {"funding_confirmed_lender", "funding_confirmed_borrower"})

    def test_confirmed_without_active_loan_says_review(self):
        self.run_notify("confirmed", None)
        for p in self.dispatched:
            self.assertEqual(p["pushTitle"], "Fondeo confirmado")
            self.assertIn("revisión", p["pushMessage"])

    def test_party_with_the_app_gets_no_whatsapp_or_sms(self):
        # The lender has the app (core push covers them); the borrower uninstalled it.
        self.run_notify("declared", with_app=[3371])
        self.assertEqual([p["eventName"] for p in self.dispatched], ["funding_declared_borrower"])
        # The email copy still goes to whoever has an address.
        self.assertEqual([e[0] for e in self.emails if e[0]], ["lender@test.mx"])

    def test_email_only_when_the_client_has_one(self):
        self.run_notify("declared")
        sent = [e for e in self.emails if e[0]]
        self.assertEqual([e[0] for e in sent], ["lender@test.mx"])

    def test_one_party_failing_does_not_stop_the_other(self):
        calls = []

        def boom(payload):
            calls.append(payload["eventName"])
            if payload["eventName"].endswith("_lender"):
                raise RuntimeError("provider down")

        self.run_notify("declared", dispatch_side_effect=boom)
        self.assertEqual(calls, ["funding_declared_lender", "funding_declared_borrower"])

    def test_without_secret_the_notice_still_goes_without_link(self):
        self.dispatched = []
        with mock.patch.dict(os.environ, {"LOAN_TICKET_LINK_SECRET": ""}), \
                mock.patch.object(loanTickets, "_funding_one", return_value=dict(FT)), \
                mock.patch.object(loanTickets, "_contact", side_effect=lambda cid: CONTACTS[cid]), \
                mock.patch.object(loanTickets, "_dispatch", side_effect=self.dispatched.append), \
                mock.patch.object(loanTickets, "_has_app", return_value=False), \
                mock.patch.object(loanTickets, "_email"):
            loanTickets.notify_funding_event(1008, 41, "declared")
        self.assertEqual(len(self.dispatched), 2)
        for p in self.dispatched:
            self.assertIsNone(p["receiptUrl"])
            self.assertEqual(p["waParams"][1], "la app GMO Prestamos")

    def test_unknown_funding_sends_nothing(self):
        with mock.patch.object(loanTickets, "_funding_one", return_value={}), \
                mock.patch.object(loanTickets, "_dispatch") as dispatch:
            loanTickets.notify_funding_event(1008, 999, "declared")
        dispatch.assert_not_called()


class TicketPageTests(unittest.TestCase):
    def render(self):
        history = [{"newStatus": "PENDING_CONFIRMATION", "created_At": "2026-11-19T18:05:00",
                    "ipAddress": "10.0.0.9", "deviceInfo": "iPhone"}]
        evidence = {"claveRastreo": "MBAN<script>", "bankFrom": "BBVA", "validationStatus": "VALID"}
        with mock.patch.object(loanTickets, "_funding_one", return_value=dict(FT)), \
                mock.patch.object(loanTickets, "_history", return_value=history), \
                mock.patch.object(loanTickets, "_evidence", return_value=evidence):
            return loanTickets.render_funding_ticket(1008, 41, "lender")

    def test_shows_the_funding_and_the_legend(self):
        page = self.render()
        for text in ("Folio", "41", "$5,000.00 MXN", "Pendiente de confirmar", "BBVA", "Prestamista",
                     "no recibe, retiene ni administra estos fondos"):
            self.assertIn(text, page)
        self.assertIn("19/11/2026 11:05", page)  # 18:05 UTC -> Hermosillo (UTC-7)

    def test_escapes_and_never_shows_audit_fields(self):
        page = self.render()
        self.assertNotIn("<script>", page)
        self.assertIn("MBAN&lt;script&gt;", page)
        self.assertNotIn("10.0.0.9", page)
        self.assertNotIn("iPhone", page)

    def test_route(self):
        app = FastAPI()
        app.include_router(loan_tickets_routes.router)
        client = TestClient(app)
        with mock.patch.dict(os.environ, SECRET):
            self.assertEqual(client.get("/comprobante/1008-funding-41-lender-xxxxxxxxxxxxxxxxxxxxxx").status_code, 404)
            token = loanTickets.ticket_link(1008, "funding", 41, "lender").rsplit("/", 1)[1]
            with mock.patch.object(loanTickets, "render_funding_ticket", return_value="<html>ok</html>") as render:
                res = client.get(f"/comprobante/{token}")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.headers["cache-control"], "no-store")
        render.assert_called_once_with(1008, 41, "lender")


class FundingHooksTests(unittest.TestCase):
    def test_declare_success_sends_the_declared_ticket(self):
        result = {"fundingTransactionId": 41, "companyId": 1008, "loanId": 88}
        result = {**result, "borrowerClientId": 2165, "amountMXN": 5000}
        with mock.patch.object(fundingTransactions, "_sp_raw", return_value=result), \
                mock.patch.object(fundingTransactions, "push_in_background") as push, \
                mock.patch.object(fundingTransactions, "notify_funding_event_async") as notify:
            res = fundingTransactions.funding_transactions_declare(
                {"fundingTransactions": [{"action": "declare", "companyId": 1008}]})
        self.assertEqual(json.loads(res.body), result)
        notify.assert_called_once_with(1008, 41, "declared")
        push.assert_called_once_with(1008, 2165, "funding_declared", amount=5000, loanId=88,
                                     fundingTransactionId=41)

    def test_declare_error_sends_nothing(self):
        with mock.patch.object(fundingTransactions, "_sp_raw", return_value={"error": "ya existe"}), \
                mock.patch.object(fundingTransactions, "push_in_background") as push, \
                mock.patch.object(fundingTransactions, "notify_funding_event_async") as notify:
            fundingTransactions.funding_transactions_declare(
                {"fundingTransactions": [{"action": "declare", "companyId": 1008}]})
        notify.assert_not_called()

    def test_confirm_sends_the_confirmed_ticket_with_the_loan_status(self):
        sp_results = [{"loanId": 88, "fundingTransactionId": 41}, dict(FT)]
        with mock.patch.object(fundingTransactions, "_sp_raw", side_effect=sp_results), \
                mock.patch.object(fundingTransactions, "_sp_loans_one", return_value={"loanId": 88}), \
                mock.patch.object(fundingTransactions, "_sp_loans_transition", return_value={}), \
                mock.patch.object(fundingTransactions, "generate_installment_schedule",
                                  new=mock.AsyncMock(return_value=JSONResponse({"ok": 1}, status_code=200))), \
                mock.patch.object(fundingTransactions, "_push_loan_active", new=mock.AsyncMock()) as core_push, \
                mock.patch.object(fundingTransactions, "notify_funding_event_async") as notify:
            res = asyncio.run(fundingTransactions.funding_transactions_confirm(
                {"fundingTransactions": [{"action": "confirm", "companyId": 1008, "fundingTransactionId": 41}]}))
        self.assertEqual(json.loads(res.body)["loanStatus"], "active")
        notify.assert_called_once_with(1008, 41, "confirmed", "active")
        core_push.assert_awaited_once()  # direct send_azure_push "Préstamo activo" stays

    def test_confirm_error_sends_nothing(self):
        with mock.patch.object(fundingTransactions, "_sp_raw", return_value={"error": "no es el acreditado"}), \
                mock.patch.object(fundingTransactions, "notify_funding_event_async") as notify:
            res = asyncio.run(fundingTransactions.funding_transactions_confirm(
                {"fundingTransactions": [{"action": "confirm", "companyId": 1008, "fundingTransactionId": 41}]}))
        self.assertEqual(res.status_code, 400)
        notify.assert_not_called()


if __name__ == "__main__":
    unittest.main()
