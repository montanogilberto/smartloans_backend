"""
Card top-ups are direct charges on the company's own Stripe account (RFC-010):
no ACTIVE company account means no charge, and the account id is never public.
No database or Stripe: both are stubbed.

Run:  venv/bin/python -m unittest tests/test_company_stripe_top_up.py -v
"""
import asyncio
import json
import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import FastAPI  # noqa: E402
from fastapi.responses import JSONResponse  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

import modules.companyPaymentAccounts as accounts  # noqa: E402
import modules.stripe_payments as sp  # noqa: E402
import routes_.companyPaymentAccounts as routes  # noqa: E402
import security.worker_key as worker_key  # noqa: E402

ACCT = "acct_company"
VALID_CLABE = "014027000000000008"
TOP_UP = {"companyId": 7, "fromClientId": 9, "toClientId": 9, "amount": 10000, "paymentType": "laundry_top_up"}


def _body(response):
    return json.loads(response.body)


class TopUpChargeTest(unittest.TestCase):
    def setUp(self):
        self.create = mock.patch.object(sp.stripe.PaymentIntent, "create",
                                        return_value={"id": "pi_1", "client_secret": "sec"}).start()
        mock.patch.object(sp.stripe, "api_key", "sk_test_real").start()
        mock.patch.object(sp, "_sp_transaction", return_value={"transactionId": 1}).start()
        mock.patch.object(sp, "log_integration").start()
        mock.patch.object(sp, "log_workflow_step").start()
        self.addCleanup(mock.patch.stopall)

    def _create(self, acct, payload=TOP_UP):
        with mock.patch.object(sp, "_company_stripe_account", return_value=acct), \
             mock.patch.object(sp, "_company_customer", return_value=self.customer):
            return asyncio.run(sp.create_payment_intent(dict(payload)))

    customer = "cus_1"

    def test_the_charge_can_keep_the_card_on_the_company_account(self):
        body = _body(self._create(ACCT))
        kwargs = self.create.call_args.kwargs
        self.assertEqual((kwargs["customer"], kwargs["setup_future_usage"]), ("cus_1", "off_session"))
        self.assertTrue(body["canSaveCard"])

    def test_no_customer_still_charges_without_saving(self):
        with mock.patch.object(self, "customer", ""):
            body = _body(self._create(ACCT))
        self.assertNotIn("setup_future_usage", self.create.call_args.kwargs)
        self.assertFalse(body["canSaveCard"])

    def test_charges_on_the_company_account_with_card_only(self):
        response = self._create(ACCT)
        kwargs = self.create.call_args.kwargs
        self.assertEqual(kwargs["stripe_account"], ACCT)
        self.assertEqual(kwargs["payment_method_types"], ["card"])
        self.assertEqual(_body(response)["stripeAccount"], ACCT)

    def test_without_an_active_account_nothing_is_charged(self):
        self.assertEqual(self._create("").status_code, 503)
        self.create.assert_not_called()

    def test_loan_payments_stay_on_the_platform(self):
        response = self._create("", {**TOP_UP, "paymentType": "loan_repayment"})
        self.assertNotIn("stripe_account", self.create.call_args.kwargs)
        self.assertNotIn("stripeAccount", _body(response))


class ConfirmTest(unittest.TestCase):
    def test_reads_the_intent_from_the_company_account(self):
        intent = {"status": "processing"}
        with mock.patch.object(sp, "_company_stripe_account", return_value=ACCT), \
             mock.patch.object(sp.stripe.PaymentIntent, "retrieve", return_value=intent) as retrieve, \
             mock.patch.object(sp, "_sp_transaction", return_value={}), \
             mock.patch.object(sp, "log_integration"), mock.patch.object(sp, "log_workflow_step"):
            asyncio.run(sp.confirm_payment_intent(
                {"paymentIntentId": "pi_1", "companyId": 7, "paymentType": "laundry_top_up"}))
        self.assertEqual(retrieve.call_args.kwargs["stripe_account"], ACCT)

    def test_a_replaced_account_still_confirms_its_own_charge(self):
        rows = [{"stripeConnectedAccountId": "acct_old"}]
        with mock.patch.object(sp, "list_accounts", return_value=rows), \
             mock.patch.object(sp, "_company_stripe_account", return_value=ACCT):
            self.assertEqual(sp._intent_account(7, "acct_old"), "acct_old")

    def test_another_companys_account_is_ignored(self):
        with mock.patch.object(sp, "list_accounts", return_value=[]), \
             mock.patch.object(sp, "_company_stripe_account", return_value=ACCT):
            self.assertEqual(sp._intent_account(7, "acct_foreign"), ACCT)

    def _confirm(self, prev):
        intent = {"status": "succeeded", "amount": 10000, "latest_charge": None}
        tx = {"transactionId": 1, "status": "succeeded", "prevStatus": prev, "paymentType": "x"}
        with mock.patch.object(sp, "_intent_account", return_value=ACCT), \
             mock.patch.object(sp.stripe.PaymentIntent, "retrieve", return_value=intent), \
             mock.patch.object(sp, "_sp_transaction", return_value=tx), \
             mock.patch.object(sp, "_send_receipt_async") as receipt, \
             mock.patch.object(sp, "log_integration"), mock.patch.object(sp, "log_workflow_step"):
            asyncio.run(sp.confirm_payment_intent(
                {"paymentIntentId": "pi_1", "companyId": 7, "paymentType": "laundry_top_up"}))
        return receipt

    def test_confirm_sends_the_receipt_when_it_settles_first(self):
        self._confirm("pending").assert_called_once()

    def test_no_second_receipt_after_the_webhook_settled(self):
        self._confirm("succeeded").assert_not_called()


class _Request:
    def __init__(self, event, signature="sig"):
        self.body_bytes = json.dumps(event).encode()
        self.headers = {"stripe-signature": signature}

    async def body(self):
        return self.body_bytes


class WebhookTest(unittest.TestCase):
    def _event(self, metadata, account=ACCT, event_type="payment_intent.succeeded"):
        return {"type": event_type, "account": account, "data": {"object": {"id": "pi_1", "metadata": metadata}}}

    def _run(self, event, secret="whsec_real", connect=""):
        self.settle = mock.AsyncMock()
        with mock.patch.object(sp, "WEBHOOK_SECRET", secret), mock.patch.object(sp, "CONNECT_WEBHOOK_SECRET", connect), \
             mock.patch.object(sp.stripe.Webhook, "construct_event"), \
             mock.patch.object(sp, "_sp_transaction", return_value=self.row) as tx, \
             mock.patch.object(sp, "_settle_wallet_top_up", new=self.settle), \
             mock.patch.object(sp, "_intent_fee_and_net", return_value=(7.6, 92.4)) as fees, \
             mock.patch.object(sp, "_send_receipt_async") as receipt, \
             mock.patch.object(sp, "log_workflow_step"):
            self.tx, self.fees, self.receipt = tx, fees, receipt
            return asyncio.run(sp.handle_webhook(_Request(event)))

    row = {"transactionId": 1, "status": "succeeded", "prevStatus": "pending"}

    def test_top_up_settles_against_the_events_account_and_sends_the_receipt(self):
        self._run(self._event({"paymentType": "laundry_top_up", "companyId": "7"}))
        self.fees.assert_called_once_with(self.row, ACCT)
        self.assertEqual(self.settle.await_args.kwargs["net_mxn"], 92.4)
        self.receipt.assert_called_once()

    def test_a_repeated_event_does_nothing(self):
        with mock.patch.object(self, "row", {**self.row, "prevStatus": "succeeded"}):
            self._run(self._event({"paymentType": "laundry_top_up"}))
        self.settle.assert_not_awaited()
        self.receipt.assert_not_called()

    def test_live_keys_never_accept_an_unverified_event(self):
        event = self._event({"paymentType": "laundry_top_up"}, account=None)
        with mock.patch.object(sp.stripe, "api_key", "sk_live_x"):
            self.assertEqual(self._run(event, secret="").status_code, 400)
        self.tx.assert_not_called()

    def test_a_companys_own_sales_are_ignored(self):
        response = self._run(self._event({}))
        self.assertEqual(response.status_code, 200)
        self.tx.assert_not_called()

    def test_an_unverified_connect_event_never_credits(self):
        response = self._run(self._event({"paymentType": "laundry_top_up"}), secret="")
        self.assertEqual(response.status_code, 400)
        self.settle.assert_not_awaited()

    def test_a_second_secret_verifies_connect_events(self):
        err = sp.stripe.SignatureVerificationError("bad", "sig")
        with mock.patch.object(sp, "WEBHOOK_SECRET", "whsec_a"), mock.patch.object(sp, "CONNECT_WEBHOOK_SECRET", "whsec_b"), \
             mock.patch.object(sp.stripe.Webhook, "construct_event", side_effect=[err, None]), \
             mock.patch.object(sp, "_sp_transaction", return_value={}), \
             mock.patch.object(sp, "_settle_wallet_top_up", new=mock.AsyncMock()), \
             mock.patch.object(sp, "log_workflow_step"):
            response = asyncio.run(sp.handle_webhook(_Request(self._event({"paymentType": "laundry_top_up"}))))
        self.assertEqual(response.status_code, 200)

    def test_account_updated_mirrors_charges_for_a_company(self):
        event = {"type": "account.updated", "data": {"object": {
            "id": ACCT, "charges_enabled": True, "metadata": {"companyId": "7"}}}}
        with mock.patch.object(sp, "sync_charges_enabled") as sync:
            self._run(event)
        sync.assert_called_once_with({"stripeConnectedAccountId": ACCT, "chargesEnabled": True})


class SaveCardTest(unittest.TestCase):
    def _answer(self, save, payment_type="laundry_top_up"):
        intent = {"metadata": {"paymentType": payment_type}, "payment_method": "pm_1"}
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(sp, "_intent_account", return_value=ACCT).start()
        mock.patch.object(sp.stripe.PaymentIntent, "retrieve", return_value=intent).start()
        mock.patch.object(sp, "log_workflow_step").start()
        self.detach = mock.patch.object(sp.stripe.PaymentMethod, "detach").start()
        return asyncio.run(sp.answer_save_card({"paymentIntentId": "pi_1", "companyId": 7, "save": save}))

    def test_yes_keeps_the_card(self):
        self.assertTrue(_body(self._answer(True))["saved"])
        self.detach.assert_not_called()

    def test_no_removes_the_card(self):
        self.assertFalse(_body(self._answer(False))["saved"])
        self.detach.assert_called_once_with("pm_1", stripe_account=ACCT)

    def test_anything_but_a_real_yes_removes_it(self):
        self._answer("true")
        self.detach.assert_called_once()

    def test_other_payments_are_refused(self):
        self.assertEqual(self._answer(False, "loan_repayment").status_code, 400)
        self.detach.assert_not_called()


class CustomerTest(unittest.TestCase):
    def test_reuses_the_clients_customer(self):
        with mock.patch.object(sp.stripe.Customer, "search", return_value={"data": [{"id": "cus_9"}]}), \
             mock.patch.object(sp.stripe.Customer, "create") as create:
            self.assertEqual(sp._company_customer(ACCT, 9), "cus_9")
        create.assert_not_called()

    def test_a_stripe_failure_never_blocks_the_top_up(self):
        with mock.patch.object(sp.stripe.Customer, "search", side_effect=RuntimeError("down")):
            self.assertEqual(sp._company_customer(ACCT, 9), "")


class OnboardingTest(unittest.TestCase):
    ROW = {"companyId": 7, "createdByUserId": 1, "returnUrl": "https://pos/x"}

    def _link(self, rows, added=None, **extra):
        self.addCleanup(mock.patch.stopall)
        self.create = mock.patch.object(sp.stripe.Account, "create", return_value={"id": "acct_new"}).start()
        mock.patch.object(sp.stripe.AccountLink, "create", return_value={"url": "https://stripe/x"}).start()
        mock.patch.object(sp, "list_accounts", return_value=rows).start()
        mock.patch.object(sp, "company_name", return_value="Tienda").start()
        mock.patch.object(sp, "log_workflow_step").start()
        self.add = mock.patch.object(sp, "add_stripe_account",
                                     **(added or {"return_value": {"companyPaymentAccountId": 5}})).start()
        return asyncio.run(sp.company_onboarding_link({"companyPaymentAccounts": [{**self.ROW, **extra}]}))

    def _stripe_row(self, status):
        return {"accountType": "stripe_connect", "purpose": sp.WALLET_TOPUP_PURPOSE,
                "accountStatus": status, "stripeConnectedAccountId": "acct_old"}

    def test_a_retry_cannot_create_a_second_stripe_account(self):
        self._link([])
        self.assertEqual(self.create.call_args.kwargs["idempotency_key"], "company-account-7-0")

    def test_an_active_account_is_reused_by_default(self):
        self._link([self._stripe_row("ACTIVE")])
        self.create.assert_not_called()

    def test_replacing_creates_a_new_account(self):
        self._link([self._stripe_row("ACTIVE")], replaceActive=True)
        self.assertEqual(self.create.call_args.kwargs["idempotency_key"], "company-account-7-1")

    def test_a_failed_save_is_reported(self):
        response = self._link([], added={"side_effect": RuntimeError("db")})
        self.assertEqual(response.status_code, 500)


class RouteTest(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(routes.router)
        self.client = TestClient(app)
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(worker_key, "WORKER_KEY", "key").start()

    def test_active_never_returns_the_account_id(self):
        rows = [{"accountType": "stripe_connect", "stripeConnectedAccountId": ACCT, "chargesEnabled": True}]
        with mock.patch.object(accounts, "_read", return_value=rows):
            body = self.client.post("/companyPaymentAccounts/active", json={"companyId": 7}).json()
        self.assertEqual(body, {"cardTopUpAvailable": True, "transferAccount": None})

    def test_a_stripe_account_without_charges_stays_off(self):
        rows = [{"accountType": "stripe_connect", "stripeConnectedAccountId": ACCT, "chargesEnabled": False}]
        with mock.patch.object(accounts, "_read", return_value=rows):
            body = self.client.post("/companyPaymentAccounts/active", json={"companyId": 7}).json()
        self.assertFalse(body["cardTopUpAvailable"])

    def test_active_shows_only_the_confirmed_clabe(self):
        row = {"holderName": "T", "clabe": VALID_CLABE, "bankName": "B", "terminalName": "X"}
        with mock.patch.object(accounts, "_read", return_value=[{**row, "accountType": "spei"}]):
            body = self.client.post("/companyPaymentAccounts/active", json={"companyId": 7}).json()
        self.assertEqual(body["transferAccount"], row)

    def _add(self, **row):
        body = {"companyPaymentAccounts": [{"action": 6, "companyId": 7, "createdByUserId": 1, "holderName": "T",
                                            "clabe": VALID_CLABE, "commissionTerminalId": 1, **row}]}
        with mock.patch.object(accounts, "_write", return_value={"value": "1", "msg": "Inserted Successfully", "error": ""}) as sp_mock, \
             mock.patch.object(accounts, "log_audit"):
            response = self.client.post("/companyPaymentAccounts/transfer-account", json=body,
                                        headers={"X-Worker-Key": "key"})
        return response.status_code, sp_mock

    def test_a_refused_write_reports_the_sp_message(self):
        with mock.patch.object(accounts, "_write", return_value={"value": "", "msg": "second_admin_required", "error": "1"}):
            response = accounts.confirm_account({"companyId": 7, "companyPaymentAccountId": 1, "verifiedByUserId": 1})
        self.assertEqual((response.status_code, _body(response)["error"]), (400, "second_admin_required"))

    def test_a_valid_clabe_is_saved_as_pending_with_its_bank(self):
        status, sp_mock = self._add()
        self.assertEqual(status, 200)
        self.assertEqual(sp_mock.call_args.args[0]["bankName"], "Santander México")

    def test_the_account_is_linked_to_its_terminal(self):
        _, sp_mock = self._add(commissionTerminalId=1)
        self.assertEqual(sp_mock.call_args.args[0]["commissionTerminalId"], 1)

    def test_a_clabe_without_a_terminal_is_refused(self):
        status, sp_mock = self._add(commissionTerminalId=None)
        self.assertEqual(status, 400)
        sp_mock.assert_not_called()

    def test_a_bad_check_digit_is_refused(self):
        status, sp_mock = self._add(clabe=VALID_CLABE[:17] + str((int(VALID_CLABE[17]) + 1) % 10))
        self.assertEqual(status, 400)
        sp_mock.assert_not_called()

    def test_registering_a_clabe_needs_an_admin(self):
        body = {"companyPaymentAccounts": [{"action": 6, "companyId": 7, "clabe": VALID_CLABE}]}
        self.assertEqual(self.client.post("/companyPaymentAccounts/transfer-account", json=body).status_code, 403)

    def test_a_failed_lookup_keeps_top_ups_off(self):
        with mock.patch.object(accounts, "_read", side_effect=RuntimeError("no table")):
            body = self.client.post("/companyPaymentAccounts/active", json={"companyId": 7}).json()
        self.assertEqual(body, {"cardTopUpAvailable": False, "transferAccount": None})

    def test_admin_routes_refuse_without_a_key_or_session(self):
        body = {"companyPaymentAccounts": [{"action": 3, "companyId": 7}]}
        for path in ("/list", "/confirm", "/stripe/onboarding-link"):
            self.assertEqual(self.client.post(f"/companyPaymentAccounts{path}", json=body).status_code, 403, path)

    def test_a_read_shaped_body_cannot_skip_the_guard_on_confirm(self):
        # action 0 reads stay open in the shared guard, so the routes must not
        # treat such a body as a write.
        body = {"companyPaymentAccounts": [{"companyId": 7, "companyPaymentAccountId": 1, "verifiedByUserId": 2}]}
        response = self.client.post("/companyPaymentAccounts/confirm", json=body)
        self.assertEqual(response.status_code, 403)


if __name__ == "__main__":
    unittest.main()
